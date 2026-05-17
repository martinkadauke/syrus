module Admin
  module SpawnedProcessesHelper
    KIND_PILL_CLASSES = {
      "agent"   => "bg-violet-100 text-violet-800",
      "grader"  => "bg-emerald-100 text-emerald-800",
      "git"     => "bg-amber-100 text-amber-800",
      "prepare" => "bg-sky-100 text-sky-800"
    }.freeze

    OUTCOME_PILL_CLASSES = {
      "succeeded"        => "bg-emerald-100 text-emerald-800",
      "failed"           => "bg-red-100 text-red-800",
      "timed_out"        => "bg-amber-100 text-amber-800",
      "silent_timed_out" => "bg-amber-100 text-amber-800",
      "aliveness_failed" => "bg-red-100 text-red-800",
      "operator_killed"  => "bg-rose-100 text-rose-800",
      "stopped"          => "bg-gray-200 text-gray-800",
      "orphaned"         => "bg-rose-100 text-rose-800"
    }.freeze

    def kind_pill_class(kind)
      KIND_PILL_CLASSES.fetch(kind, "bg-gray-100 text-gray-800")
    end

    def outcome_pill_class(outcome)
      OUTCOME_PILL_CLASSES.fetch(outcome, "bg-gray-100 text-gray-800")
    end

    # Compact human label — "3.2s", "1m 14s", "23m", "1h 04m".
    # Returns "—" for nil or non-finite values.
    def duration_label(seconds)
      return "—" if seconds.nil? || !seconds.is_a?(Numeric) || !seconds.finite?

      s = seconds.to_f
      return format("%.1fs", s) if s < 60
      return "#{(s / 60).floor}m #{(s % 60).round}s" if s < 3600

      hours = (s / 3600).floor
      mins = ((s % 3600) / 60).floor
      format("%dh %02dm", hours, mins)
    end

    # Convert host_metrics keys to friendly display values.
    def format_metric(key, value)
      return "—" if value.nil?

      case key.to_sym
      when :rss_bytes, :vsz_bytes
        number_to_human_size(value)
      when :cpu_percent
        format("%.1f%%", value)
      when :cpu_seconds
        format("%.1fs", value)
      else
        value.to_s
      end
    end
  end
end
