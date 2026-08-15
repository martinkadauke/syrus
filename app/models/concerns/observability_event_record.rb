module ObservabilityEventRecord
  extend ActiveSupport::Concern

  included do
    scope :recent_first, -> { order(occurred_at: :desc, id: :desc) }
  end

  class_methods do
    def parse_event_time(value)
      return value if value.is_a?(Time)
      return value.to_time if value.respond_to?(:to_time)
      return if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def normalized_event_json(value)
      JSON.parse(JSON.generate(value || {}))
    rescue JSON::ParserError, TypeError
      {}
    end
  end
end
