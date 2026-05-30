module Api
  module V1
    module App
      module Admin
        class TranscriptsController < BaseController
          def show
            result = ::Admin::Transcripts::Payload.new(params: params).show(params[:run_id])
            if result[:error]
              render_error(result.dig(:error, :code), result.dig(:error, :message), status: result[:status])
              return
            end

            render json: result
          end
        end
      end
    end
  end
end
