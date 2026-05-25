module Api
  module V1
    module Admin
      # API mirror of the operator console kill switches.
      #
      # GET  /api/v1/admin/console
      # POST /api/v1/admin/console/pause_polling
      # POST /api/v1/admin/console/unpause_polling
      # POST /api/v1/admin/console/pause_runs
      # POST /api/v1/admin/console/unpause_runs
      class ConsoleController < BaseController
        def show
          render json: payload
        end

        def pause_polling
          update_flag!(polling_paused: true, action: :pause_polling)
        end

        def unpause_polling
          update_flag!(polling_paused: false, action: :unpause_polling)
        end

        def pause_runs
          update_flag!(runs_paused: true, action: :pause_runs)
        end

        def unpause_runs
          update_flag!(runs_paused: false, action: :unpause_runs)
        end

        private

        def update_flag!(attrs)
          action = attrs.delete(:action)
          AppSetting.current.update!(attrs)
          AdminAction.log!(user: current_api_user, action: action, params: { source: "api" })
          render json: payload.merge(ok: true)
        end

        def payload
          settings = AppSetting.current
          {
            settings: {
              polling_paused: settings.polling_paused,
              runs_paused: settings.runs_paused,
              signups_open: settings.signups_open,
              max_job_failures: settings.max_job_failures,
              grade_max_iterations: settings.grade_max_iterations
            },
            recent_admin_actions: AdminAction.recent.includes(:user).map do |action|
              {
                id: action.id,
                action: action.action,
                performed_at: action.performed_at,
                user_email: action.user.email_address,
                params: action.params
              }
            end
          }
        end
      end
    end
  end
end
