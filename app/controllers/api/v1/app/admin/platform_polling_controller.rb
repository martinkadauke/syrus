module Api
  module V1
    module App
      module Admin
        class PlatformPollingController < BaseController
          def start
            started = PlatformPollingJob.start_all!
            render json: { started: started }
          end
        end
      end
    end
  end
end
