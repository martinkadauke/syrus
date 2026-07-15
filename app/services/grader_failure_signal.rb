class GraderFailureSignal
  TIMEOUT_EXIT_CODE = 124
  TIMEOUT_PATTERNS = [
    /\btest timed out\b/i,
    /\btimed out in \d+(?:\.\d+)?\s*ms\b/i,
    /\btimed out after \d+(?:\.\d+)?\s*(?:ms|s|seconds?|m|minutes?)\b/i,
    /\[timed out after \d+(?:\.\d+)?\s*minutes?\]/i,
    /\bexceeded timeout of \d+(?:\.\d+)?\s*ms\b/i,
    /\btimeout - async callback was not invoked\b/i
  ].freeze

  class << self
    def timeout_like_step?(step)
      timeout_like_entry?(step.details || {})
    end

    def timeout_like_entry?(entry)
      entry = entry.to_h
      return true if truthy?(value(entry, :timed_out))

      if !key?(entry, :timed_out) && value(entry, :exit_code).to_i == TIMEOUT_EXIT_CODE
        return true
      end

      timeout_output?(output_for(entry))
    end

    def timeout_only_latest_failure?(iterations)
      failed = latest_failed_required_entries(iterations)
      failed.any? && failed.all? { |entry| timeout_like_entry?(entry) }
    end

    def latest_failed_required_entries(iterations)
      Array(iterations).reverse_each do |entries|
        failed = failed_required_entries(Array(entries))
        return failed if failed.any?
      end

      []
    end

    def failed_required_entries(entries)
      Array(entries).select do |entry|
        status = value(entry.to_h, :status).to_s
        status == "failed" && required?(entry.to_h)
      end
    end

    private

    def timeout_output?(output)
      output.to_s.match?(Regexp.union(TIMEOUT_PATTERNS))
    end

    def output_for(entry)
      output = value(entry, :output) || value(entry, :log)
      output ||= [ value(entry, :stdout), value(entry, :stderr) ].compact.join
      output.to_s
    end

    def required?(entry)
      required = value(entry, :required)
      required.nil? || truthy?(required)
    end

    def truthy?(value)
      value == true || value.to_s == "true"
    end

    def key?(entry, key)
      entry.key?(key.to_s) || entry.key?(key.to_sym)
    end

    def value(entry, key)
      string_key = key.to_s
      symbol_key = key.to_sym
      return entry[string_key] if entry.key?(string_key)
      return entry[symbol_key] if entry.key?(symbol_key)

      nil
    end
  end
end
