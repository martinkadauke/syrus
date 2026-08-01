module Admin
  class PerformancePayload
    DEFAULT_LIMIT = 100

    def initialize(params: {})
      @params = params
    end

    def as_json(*)
      events = PerformanceLogging::Store.recent(limit: limit)
      {
        enabled: Feature.enabled?(PerformanceLogging::FEATURE_SLUG),
        thresholds: PerformanceLogging.thresholds,
        storage: storage_payload,
        summaries: summaries_payload(events),
        events: events
      }
    end

    private

    attr_reader :params

    def limit
      raw = Integer(params[:limit], exception: false) || DEFAULT_LIMIT
      PerformanceLogging::Store.clamp_limit(raw)
    end

    def storage_payload
      {
        kind: cache_store_name,
        cache_key: PerformanceLogging::Store::CACHE_KEY,
        max_events: PerformanceLogging::Store::MAX_EVENTS,
        expires_in_seconds: PerformanceLogging::Store::EXPIRES_IN.to_i
      }
    end

    def cache_store_name
      Array(Rails.application.config.cache_store).first.to_s
    end

    def summaries_payload(events)
      {
        slow_requests: grouped_slow_requests(events),
        slow_phases: grouped_slow_phases(events),
        sql_fingerprints: grouped_sql_fingerprints(events)
      }
    end

    def grouped_slow_requests(events)
      grouped = events.select { |event| event["event"] == PerformanceLogging::SLOW_REQUEST_EVENT }
        .group_by { |event| [ event["method"], event["path"], event["controller"], event["action"] ] }

      grouped.map do |(method, path, controller, action), rows|
        durations = rows.map { |event| event["duration_ms"].to_f }
        {
          method: method,
          path: path,
          controller: controller,
          action: action,
          count: rows.size,
          total_duration_ms: durations.sum.round(1),
          average_duration_ms: average(durations),
          max_duration_ms: durations.max&.round(1),
          average_sql_count: average(rows.map { |event| event["sql_count"].to_i }),
          average_sql_duration_ms: average(rows.map { |event| event["sql_duration_ms"].to_f }),
          last_seen_at: rows.map { |event| event["occurred_at"] }.compact.max
        }
      end.sort_by { |row| [ -row[:total_duration_ms].to_f, -row[:count] ] }
    end

    def grouped_slow_phases(events)
      grouped = events.select { |event| event["event"] == PerformanceLogging::SLOW_PHASE_EVENT }
        .group_by { |event| event["phase"] }

      grouped.map do |phase, rows|
        durations = rows.map { |event| event["duration_ms"].to_f }
        {
          phase: phase,
          count: rows.size,
          total_duration_ms: durations.sum.round(1),
          average_duration_ms: average(durations),
          max_duration_ms: durations.max&.round(1),
          last_seen_at: rows.map { |event| event["occurred_at"] }.compact.max,
          recent_metadata: rows.first["metadata"]
        }
      end.sort_by { |row| [ -row[:total_duration_ms].to_f, -row[:count] ] }
    end

    def grouped_sql_fingerprints(events)
      rows = []
      events.each do |event|
        if event["event"] == PerformanceLogging::SLOW_SQL_EVENT && event["fingerprint"].present?
          rows << {
            "fingerprint" => event["fingerprint"],
            "sample_sql" => event["sql"],
            "name" => event["name"],
            "count" => 1,
            "total_duration_ms" => event["duration_ms"].to_f,
            "max_duration_ms" => event["duration_ms"].to_f
          }
        end
        Array(event["top_sql_fingerprints"]).each { |entry| rows << entry }
      end

      grouped = rows.group_by { |row| row["fingerprint"] }
      grouped.map do |fingerprint, entries|
        total = entries.sum { |entry| entry["total_duration_ms"].to_f }
        count = entries.sum { |entry| entry["count"].to_i }
        {
          fingerprint: fingerprint,
          sample_sql: entries.find { |entry| entry["sample_sql"].present? }&.fetch("sample_sql"),
          name: entries.find { |entry| entry["name"].present? }&.fetch("name"),
          count: count,
          total_duration_ms: total.round(1),
          average_duration_ms: count.positive? ? (total / count).round(1) : nil,
          max_duration_ms: entries.map { |entry| entry["max_duration_ms"].to_f }.max&.round(1)
        }
      end.sort_by { |row| [ -row[:total_duration_ms].to_f, -row[:count] ] }
    end

    def average(values)
      values = values.compact
      return nil if values.empty?

      (values.sum.to_f / values.size).round(1)
    end
  end
end
