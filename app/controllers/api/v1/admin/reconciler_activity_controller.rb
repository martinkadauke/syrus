module Api
  module V1
    module Admin
      class ReconcilerActivityController < BaseController
        def index
          render json: ::Admin::ReconcilerActivityPayload.new(params: params).as_json
        end
      end
    end
  end
end
