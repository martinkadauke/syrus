module Api
  module V1
    module App
      module Admin
        class PlatformPollingController < BaseController
          def start
            started = PlatformPollingJob.registry.filter_map do |klass|
              next if SolidQueue::Job.where(class_name: klass.name, finished_at: nil).exists?
              klass.perform_later
              klass.name
            end
            render json: { started: started }
          end
        end
      end
    end
  end
end
