module PerformanceLogging
  FEATURE_SLUG = :performance_logging
  SLOW_REQUEST_EVENT = "syrus.performance.slow_request"
  SLOW_SQL_EVENT = "syrus.performance.slow_sql"
  SLOW_PHASE_EVENT = "syrus.performance.slow_phase"

  DEFAULT_SLOW_REQUEST_MS = 1_000.0
  DEFAULT_SLOW_SQL_MS = 250.0
  DEFAULT_SLOW_PHASE_MS = 250.0
  TOP_SQL_FINGERPRINT_LIMIT = 10
  MAX_SQL_FINGERPRINTS_PER_REQUEST = 100

  module Store
    CACHE_KEY = "syrus:performance_logging:events:v1"
    MAX_EVENTS = 200
    EXPIRES_IN = 6.hours

    module_function

    def append(event)
      PerformanceLogging.suppress do
        events = Array(Rails.cache.read(CACHE_KEY))
        events << event
        Rails.cache.write(CACHE_KEY, events.last(MAX_EVENTS), expires_in: EXPIRES_IN)
      end
    rescue StandardError
      nil
    end

    def recent(limit: MAX_EVENTS)
      limit = clamp_limit(limit)
      PerformanceLogging.suppress do
        Array(Rails.cache.read(CACHE_KEY)).last(limit).reverse
      end
    rescue StandardError
      []
    end

    def clear!
      PerformanceLogging.suppress { Rails.cache.delete(CACHE_KEY) }
    rescue StandardError
      nil
    end

    def clamp_limit(limit)
      [[limit.to_i, 1].max, MAX_EVENTS].min
    end
  end

  module_function

  def with_request_context(context)
    Current.performance_request_context = safe_context(context)
    Current.performance_sql_count = 0
    Current.performance_sql_duration_ms = 0.0
    Current.performance_slow_sql_count = 0
    Current.performance_sql_fingerprints = {}
    yield
  end

  def merge_request_context(context)
    Current.performance_request_context = request_context.merge(safe_context(context))
  end

  def enabled?
    return false if suppressed?
    return Current.performance_logging_enabled unless Current.performance_logging_enabled.nil?

    Current.performance_logging_enabled = if Rails.env.production?
      feature_enabled?
    else
      env_enabled? || feature_enabled?
    end
  end

  def record_sql(payload, duration_ms)
    return if suppressed? || ignored_sql?(payload)
    return unless enabled?

    Current.performance_sql_count = Current.performance_sql_count.to_i + 1
    Current.performance_sql_duration_ms = Current.performance_sql_duration_ms.to_f + duration_ms.to_f
    record_sql_fingerprint(payload, duration_ms)
    return if duration_ms.to_f < slow_sql_threshold_ms

    Current.performance_slow_sql_count = Current.performance_slow_sql_count.to_i + 1
    emit(
      base_event(SLOW_SQL_EVENT).merge(
        request_context,
        "duration_ms" => rounded_duration(duration_ms),
        "name" => safe_string(payload[:name], 200),
        "sql" => safe_string(payload[:sql], 2_000),
        "fingerprint" => fingerprint_sql(payload[:sql])
      ).compact
    )
  end

  def record_request(payload, duration_ms)
    return if suppressed?
    return unless enabled?
    return if duration_ms.to_f < slow_request_threshold_ms

    emit(
      base_event(SLOW_REQUEST_EVENT).merge(
        request_context_from_payload(payload),
        "duration_ms" => rounded_duration(duration_ms),
        "method" => safe_string(payload[:method], 20),
        "path" => safe_string(payload[:path], 500),
        "controller" => safe_string(payload[:controller], 200),
        "action" => safe_string(payload[:action], 100),
        "format" => safe_string(payload[:format], 50),
        "status" => payload[:status],
        "view_runtime_ms" => rounded_duration(payload[:view_runtime]),
        "db_runtime_ms" => rounded_duration(payload[:db_runtime]),
        "sql_count" => Current.performance_sql_count.to_i,
        "sql_duration_ms" => rounded_duration(Current.performance_sql_duration_ms),
        "slow_sql_count" => Current.performance_slow_sql_count.to_i,
        "top_sql_fingerprints" => top_sql_fingerprints
      ).compact
    )
  end

  def phase(name, metadata = {})
    return yield unless enabled?

    started_at = monotonic_ms
    yield
  ensure
    duration_ms = monotonic_ms - started_at if started_at
    if duration_ms && duration_ms >= slow_phase_threshold_ms
      emit(
        base_event(SLOW_PHASE_EVENT).merge(
          request_context,
          "duration_ms" => rounded_duration(duration_ms),
          "phase" => safe_string(name, 200),
          "metadata" => safe_metadata(metadata)
        )
      )
    end
  end

  def slow_request_threshold_ms
    threshold_from_env("SYRUS_PERFORMANCE_SLOW_REQUEST_MS", DEFAULT_SLOW_REQUEST_MS)
  end

  def slow_sql_threshold_ms
    threshold_from_env("SYRUS_PERFORMANCE_SLOW_SQL_MS", DEFAULT_SLOW_SQL_MS)
  end

  def slow_phase_threshold_ms
    threshold_from_env("SYRUS_PERFORMANCE_SLOW_PHASE_MS", DEFAULT_SLOW_PHASE_MS)
  end

  def thresholds
    {
      slow_request_ms: slow_request_threshold_ms,
      slow_sql_ms: slow_sql_threshold_ms,
      slow_phase_ms: slow_phase_threshold_ms,
      top_sql_fingerprint_limit: TOP_SQL_FINGERPRINT_LIMIT,
      max_sql_fingerprints_per_request: MAX_SQL_FINGERPRINTS_PER_REQUEST
    }
  end

  def suppress
    previous = Thread.current[:syrus_performance_logging_suppressed]
    Thread.current[:syrus_performance_logging_suppressed] = true
    yield
  ensure
    Thread.current[:syrus_performance_logging_suppressed] = previous
  end

  def suppressed?
    Thread.current[:syrus_performance_logging_suppressed]
  end

  def feature_enabled?
    suppress { Feature.enabled?(FEATURE_SLUG) }
  rescue StandardError
    false
  end

  def env_enabled?
    ActiveModel::Type::Boolean.new.cast(ENV["SYRUS_PERFORMANCE_LOGGING"])
  end

  def ignored_sql?(payload)
    return true if payload[:cached] || payload[:name] == "SCHEMA"

    payload[:sql].to_s.match?(/\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE SAVEPOINT)\b/i)
  end

  def emit(event)
    Rails.logger.info(event.to_json)
    Store.append(event)
  rescue StandardError
    nil
  end

  def base_event(name)
    {
      "event" => name,
      "occurred_at" => Time.current.iso8601(6),
      "app_revision" => SyrusVersion.current,
      "pid" => Process.pid
    }
  end

  def request_context
    (Current.performance_request_context || {}).to_h
  end

  def request_context_from_payload(payload)
    request = payload[:request]
    request_context.merge(
      "request_id" => safe_string(request&.request_id || payload[:request_id] || request_context["request_id"], 100),
      "method" => safe_string(payload[:method] || request_context["method"], 20),
      "path" => safe_string(payload[:path] || request_context["path"], 500),
      "controller" => safe_string(payload[:controller] || request_context["controller"], 200),
      "action" => safe_string(payload[:action] || request_context["action"], 100)
    ).compact_blank
  end

  def safe_context(context)
    context.to_h.filter_map do |key, value|
      next if value.nil?

      sanitized = case key.to_sym
      when :admin
        ActiveModel::Type::Boolean.new.cast(value)
      when :user_id
        Integer(value, exception: false)
      when :request_id
        safe_string(value, 100)
      when :method
        safe_string(value, 20)
      when :path
        safe_string(value, 500)
      when :controller
        safe_string(value, 200)
      when :action
        safe_string(value, 100)
      else
        safe_string(value, 500)
      end
      [ key.to_s, sanitized ] unless sanitized.nil?
    end.to_h
  end

  def record_sql_fingerprint(payload, duration_ms)
    fingerprints = Current.performance_sql_fingerprints ||= {}
    fingerprint = fingerprint_sql(payload[:sql])
    return if fingerprint.blank?
    return if fingerprints.size >= MAX_SQL_FINGERPRINTS_PER_REQUEST && !fingerprints.key?(fingerprint)

    entry = fingerprints[fingerprint] ||= {
      "fingerprint" => fingerprint,
      "sample_sql" => safe_string(payload[:sql], 1_000),
      "name" => safe_string(payload[:name], 200),
      "count" => 0,
      "total_duration_ms" => 0.0,
      "max_duration_ms" => 0.0
    }
    duration = duration_ms.to_f
    entry["count"] += 1
    entry["total_duration_ms"] += duration
    entry["max_duration_ms"] = [ entry["max_duration_ms"], duration ].max
  end

  def top_sql_fingerprints
    (Current.performance_sql_fingerprints || {}).to_h.values
      .sort_by { |entry| [ -entry["total_duration_ms"].to_f, -entry["count"].to_i, entry["fingerprint"].to_s ] }
      .first(TOP_SQL_FINGERPRINT_LIMIT)
      .map do |entry|
        entry.merge(
          "total_duration_ms" => rounded_duration(entry["total_duration_ms"]),
          "max_duration_ms" => rounded_duration(entry["max_duration_ms"])
        )
      end
  end

  def fingerprint_sql(sql)
    safe_string(sql, 4_000)
      .gsub(/\b0x[0-9a-f]+\b/i, "?")
      .gsub(/'(?:''|[^'])*'/, "?")
      .gsub(/"(?:\"\"|[^"])*"/, "?")
      .gsub(/\b\d+\b/, "?")
      .gsub(/\s+/, " ")
      .strip
      .safe_byteslice(0, 1_000)
  end

  def safe_string(value, limit)
    value.to_s.gsub(/[[:space:]]+/, " ").strip.safe_byteslice(0, limit)
  end

  def safe_metadata(metadata)
    metadata.to_h.to_h do |key, value|
      [ safe_string(key, 100), safe_string(value, 500) ]
    end
  end

  def rounded_duration(value)
    return nil if value.nil?

    value.to_f.round(1)
  end

  def threshold_from_env(name, fallback)
    Float(ENV.fetch(name, fallback))
  rescue ArgumentError, TypeError
    fallback
  end

  def monotonic_ms
    Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1_000.0
  end
end
