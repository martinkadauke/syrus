module Admin
  module SpawnedProcesses
    class Payload
      PER_PAGE = 100

      def initialize(params:, per_page: PER_PAGE)
        @params = params
        @per_page = per_page
      end

      def index
        scope = SpawnedProcess.order(started_at: :desc).limit(@per_page)
        scope = apply_state_filter(scope)
        scope = scope.where(kind: params[:kind]) if SpawnedProcess::KINDS.include?(params[:kind])
        scope = scope.where(hostname: params[:hostname]) if params[:hostname].present?
        scope = scope.where(run_id: params[:run_id]) if params[:run_id].present?
        scope = scope.where(workflow_id: params[:workflow_id]) if params[:workflow_id].present?
        scope = scope.where("started_at >= ?", Time.zone.parse(params[:since])) if params[:since].present?

        {
          processes: scope.to_a.map { |process| serialize(process) },
          running_total: SpawnedProcess.running.count
        }
      end

      def show(id)
        serialize(SpawnedProcess.find(id), include_host_metrics: true)
      end

      def kill(id, user:)
        process = SpawnedProcess.find(id)
        return already_finished_payload(process) if process.finished?

        process.request_kill!(user: user)
        serialize(process.reload, include_host_metrics: true)
      end

      private

      attr_reader :params

      def apply_state_filter(scope)
        case params[:state]
        when "running"  then scope.running
        when "finished" then scope.finished
        when "all"      then scope
        else
          scope.where("finished_at IS NULL OR finished_at >= ?", 1.hour.ago)
        end
      end

      def already_finished_payload(process)
        {
          error: {
            code: "already_finished",
            message: "Process is finalized (#{process.outcome})."
          },
          status: :conflict
        }
      end

      def serialize(process, include_host_metrics: false)
        payload = {
          id: process.id,
          kind: process.kind,
          command: process.command,
          workdir: process.workdir,
          hostname: process.hostname,
          pid: process.pid,
          pgid: process.pgid,
          started_at: process.started_at&.iso8601,
          last_chunk_at: process.last_chunk_at&.iso8601,
          finished_at: process.finished_at&.iso8601,
          duration_s: process.duration_s,
          exit_status: process.exit_status,
          outcome: process.outcome,
          wall_timeout_s: process.wall_timeout_s,
          silent_timeout_s: process.silent_timeout_s,
          run_id: process.run_id,
          workflow_id: process.workflow_id,
          stale: process.stale?,
          kill_requested_at: process.kill_requested_at&.iso8601,
          kill_requested_by_user_id: process.kill_requested_by_user_id
        }
        payload[:host_metrics] = process.host_metrics if include_host_metrics
        payload
      end
    end
  end
end
