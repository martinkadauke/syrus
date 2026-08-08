module Api
  module V1
    module Admin
      class PerformanceController < BaseController
        def show
          return render json: { error: "syrus_dev_plugin_disabled" }, status: :not_found unless SyrusDev.enabled?

          render json: PerformanceLogging.suppress { ::SyrusDev::PerformancePayload.new(params: params).as_json }
        end
      end
    end
  end
end
