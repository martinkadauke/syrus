module Api
  module V1
    module Admin
      # Mirror of Admin::SpawnedProcessesController. Subprocess
      # inventory with the same filters as the HTML page plus
      # programmatic kill.
      #
      #   GET  /api/v1/admin/processes
      #     - ?state=running|finished|all (default: active+recent-1h)
      #     - ?kind=agent|grader|git|prepare
      #     - ?hostname=<pod-name>
      #     - ?run_id=<id>
      #     - ?workflow_id=<id>
      #     - ?since=ISO8601 (started_at >= since)
      #   GET  /api/v1/admin/processes/:id  — detail + host metrics
      #   POST /api/v1/admin/processes/:id/kill — stamp kill_requested_at
      class SpawnedProcessesController < BaseController
        def index
          render json: payload.index
        rescue ArgumentError, TypeError => e
          render json: { error: { code: "bad_request", message: e.message } }, status: :bad_request
        end

        def show
          render json: payload.show(params[:id])
        end

        def kill
          result = payload.kill(params[:id], user: current_api_user)
          if result[:error]
            render json: { error: result[:error] }, status: result[:status]
            return
          end

          render json: result
        end

        private

        def payload
          ::Admin::SpawnedProcesses::Payload.new(params: params)
        end
      end
    end
  end
end
