module Api
  module V1
    module App
      class BootstrapController < BaseController
        def show
          render json: AppApi::BootstrapSerializer.new(
            user: Current.user,
            csrf_token: form_authenticity_token,
            default_chat_path: default_chat_path
          ).as_json
        end
      end
    end
  end
end
