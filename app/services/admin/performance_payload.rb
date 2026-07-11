module Admin
  class PerformancePayload
    DEFAULT_LIMIT = 100

    def initialize(params: {})
      @params = params
    end

    def as_json(*)
      {
        enabled: Feature.enabled?(PerformanceLogging::FEATURE_SLUG),
        thresholds: PerformanceLogging.thresholds,
        storage: storage_payload,
        events: PerformanceLogging::Store.recent(limit: limit)
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
  end
end
