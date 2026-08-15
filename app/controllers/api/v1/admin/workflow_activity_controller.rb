module Api
  module V1
    module Admin
      class WorkflowActivityController < BaseController
        def index
          render json: ::Admin::WorkflowActivityPayload.new(params: params).as_json
        end
      end
    end
  end
end
