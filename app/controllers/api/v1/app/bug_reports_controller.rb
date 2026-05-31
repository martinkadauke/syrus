module Api
  module V1
    module App
      class BugReportsController < BaseController
        def create
          result = ::BugReports::Creator.new(user: Current.user).call(
            title: params[:title],
            description: params[:description],
            screenshot: params[:screenshot]
          )

          if result.success?
            render json: { message: "Bug report queued.", job_id: result.job.id }, status: :created
          else
            render_error("validation_failed", result.error, status: :unprocessable_content)
          end
        end
      end
    end
  end
end
