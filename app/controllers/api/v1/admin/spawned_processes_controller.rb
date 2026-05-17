module Api
  module V1
    module Admin
      # Mirror of Admin::SpawnedProcessesController. Subprocess
      # inventory with the same filters as the HTML page plus
      # programmatic kill.
      #
      #   GET  /api/v1/admin/processes
      #     - ?state=running|finished|all (default: active+recent-1h)
      #     - ?kind=agent|grader|git|prepare
      #     - ?hostname=<pod-name>
      #     - ?run_id=<id>
      #     - ?workflow_id=<id>
      #     - ?since=ISO8601 (started_at >= since)
      #   GET  /api/v1/admin/processes/:id  — detail + host metrics
      #   POST /api/v1/admin/processes/:id/kill — stamp kill_requested_at
      class SpawnedProcessesController < BaseController
        PER_PAGE = 100

        def index
          scope = SpawnedProcess.order(started_at: :desc).limit(PER_PAGE)
          scope = apply_state_filter(scope)
          scope = scope.where(kind: params[:kind]) if SpawnedProcess::KINDS.include?(params[:kind])
          scope = scope.where(hostname: params[:hostname]) if params[:hostname].present?
          scope = scope.where(run_id: params[:run_id]) if params[:run_id].present?
          scope = scope.where(workflow_id: params[:workflow_id]) if params[:workflow_id].present?
          if params[:since].present?
            scope = scope.where("started_at >= ?", Time.zone.parse(params[:since]))
          end

          render json: {
            processes: scope.to_a.map { |sp| serialize(sp) },
            running_total: SpawnedProcess.running.count
          }
        rescue ArgumentError, TypeError => e
          render json: { error: { code: "bad_request", message: e.message } }, status: :bad_request
        end

        def show
          sp = SpawnedProcess.find(params[:id])
          render json: serialize(sp, include_host_metrics: true)
        end

        def kill
          sp = SpawnedProcess.find(params[:id])
          if sp.finished?
            render json: {
              error: { code: "already_finished", message: "Process is finalized (#{sp.outcome})." }
            }, status: :conflict
            return
          end

          sp.request_kill!(user: Current.user)
          render json: serialize(sp.reload, include_host_metrics: true)
        end

        private

        def apply_state_filter(scope)
          case params[:state]
          when "running"  then scope.running
          when "finished" then scope.finished
          when "all"      then scope
          else
            scope.where("finished_at IS NULL OR finished_at >= ?", 1.hour.ago)
          end
        end

        def serialize(sp, include_host_metrics: false)
          payload = {
            id: sp.id,
            kind: sp.kind,
            command: sp.command,
            workdir: sp.workdir,
            hostname: sp.hostname,
            pid: sp.pid,
            pgid: sp.pgid,
            started_at: sp.started_at&.iso8601,
            last_chunk_at: sp.last_chunk_at&.iso8601,
            finished_at: sp.finished_at&.iso8601,
            duration_s: sp.duration_s,
            exit_status: sp.exit_status,
            outcome: sp.outcome,
            wall_timeout_s: sp.wall_timeout_s,
            silent_timeout_s: sp.silent_timeout_s,
            run_id: sp.run_id,
            workflow_id: sp.workflow_id,
            stale: sp.stale?,
            kill_requested_at: sp.kill_requested_at&.iso8601,
            kill_requested_by_user_id: sp.kill_requested_by_user_id
          }
          payload[:host_metrics] = sp.host_metrics if include_host_metrics
          payload
        end
      end
    end
  end
end
