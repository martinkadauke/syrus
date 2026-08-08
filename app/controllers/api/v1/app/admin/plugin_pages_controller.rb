module Api
  module V1
    module App
      module Admin
        class PluginPagesController < BaseController
          def index
            render json: ::Admin::PluginPagesPayload.new.as_json
          end
        end
      end
    end
  end
end
