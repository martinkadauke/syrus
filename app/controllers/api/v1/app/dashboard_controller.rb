module Api
  module V1
    module App
      class DashboardController < BaseController
        def preferences
          subject = params.require(:subject)

          if params.key?(:sort_column) || params.key?(:sort_direction)
            Current.user.update_dashboard_sort!(
              subject: subject,
              column: params.require(:sort_column),
              direction: params.require(:sort_direction)
            )
          end

          if params.key?(:visible_columns)
            Current.user.update_dashboard_columns!(
              subject: subject,
              columns: params[:visible_columns]
            )
          end

          if params.key?(:kanban_lanes)
            Current.user.update_dashboard_kanban_lanes!(
              subject: subject,
              lanes: params[:kanban_lanes]
            )
          end

          render json: {
            message: "Dashboard preferences updated.",
            dashboard_preferences: Current.user.reload.dashboard_preferences
          }
        rescue ActionController::ParameterMissing, ArgumentError => e
          render_error("validation_failed", e.message, status: :unprocessable_content)
        end

        def landing_pause
          Current.user.update!(landing_paused: !Current.user.landing_paused?)
          LandingQueueProcessorJob.perform_later unless Current.user.landing_paused?

          render json: {
            message: Current.user.landing_paused? ? "Landing paused." : "Landing resumed.",
            landing_paused: Current.user.landing_paused?
          }
        end

        def epic_auto_approval
          epic = Current.user.epics.find(params[:id])
          epic.update!(params.expect(epic: [ :auto_approve_mode ]))

          render json: {
            message: "Epic auto-approval updated.",
            epic: {
              id: epic.id,
              auto_approve_mode: epic.auto_approve_mode
            }
          }
        rescue ActiveRecord::RecordInvalid => e
          render_error("validation_failed", e.record.errors.full_messages.to_sentence, status: :unprocessable_content)
        end
      end
    end
  end
end
