module Api
  module V1
    module Admin
      # User directory for external admin API clients. The browser SPA
      # uses the sibling app API namespace.
      #
      #   GET /api/v1/admin/users          — filtered list
      #   GET /api/v1/admin/users/:id      — full user detail
      class UsersController < BaseController
        def index
          render json: payload.index
        end

        def show
          render json: payload.show(params[:id])
        end

        private

        def payload
          ::Admin::Users::Payload.new(params: params, actor: current_api_user)
        end
      end
    end
  end
end
