module Api
  module V1
    module App
      class TerminalSessionsController < BaseController
        before_action :require_terminal_feature

        def index
          render json: sessions_payload
        end

        def create
          session = Current.user.terminal_sessions.create!(
            workflow: selected_workflow,
            name: session_name,
            working_directory: working_directory,
            auth_token: SecureRandom.hex(32),
            started_at: Time.current
          )
          TerminalSessionJob.perform_later(session.id)

          TerminalSessionJob.perform_later(session.id)

          render json: { session: session_json(session) }, status: :created
        end

        def show
          render json: { session: session_json(find_session) }
        end

        def kill
          destroy
        end

        def destroy
          session = find_session
          session.update!(finished_at: Time.current, outcome: "killed") if session.running?

          render json: { session: session_json(session) }
        end

        private

        def require_terminal_feature
          render_terminal_disabled unless Feature.terminal_enabled?
        end

        def find_session
          Current.user.terminal_sessions.find(params[:id])
        end

        def sessions_payload
          {
            sessions: Current.user.terminal_sessions.running.order(started_at: :desc).map { |session| session_json(session) },
            workspaces: workspace_json
          }
        end

        def session_json(session)
          ::App::TerminalSessionSerializer.render(session)
        end

        def workspace_json
          scratch = {
            id: nil,
            label: "Scratch",
            working_directory: Rails.root.to_s,
            kind: "scratch"
          }
          workflows = Current.user.workflows
            .includes(job: :repository)
            .order(created_at: :desc)
            .limit(10)
            .map do |workflow|
              {
                id: workflow.id,
                label: "#{workflow.slug} - #{workflow.job.title}",
                working_directory: WorkflowWorkspace.path_for(workflow).to_s,
                kind: "workflow"
              }
            end

          [scratch, *workflows]
        end

        def selected_workflow
          return @selected_workflow if defined?(@selected_workflow)

          workflow_id = terminal_session_params[:workflow_id]
          return @selected_workflow = nil if workflow_id.blank?

          @selected_workflow = Current.user.workflows.find(workflow_id)
        end

        def working_directory
          if selected_workflow
            WorkflowWorkspace.path_for(selected_workflow).to_s
          elsif terminal_session_params[:working_directory].present?
            terminal_session_params[:working_directory]
          else
            Rails.root.to_s
          end
        end

        def session_name
          terminal_session_params[:name].presence || selected_workflow&.slug || "Scratch"
        end

        def terminal_session_params
          return params.permit(:workflow_id, :working_directory, :name) unless params[:terminal_session].is_a?(ActionController::Parameters)

          params.require(:terminal_session).permit(:workflow_id, :working_directory, :name)
        end

        def render_terminal_disabled
          render_error("terminal_disabled", "Terminal is not enabled.", status: :not_found)
        end
      end
    end
  end
end
