module Api
  module V1
    module App
      module Admin
        class BaseController < Api::V1::App::BaseController
          before_action :require_admin
        end
      end
    end
  end
end
