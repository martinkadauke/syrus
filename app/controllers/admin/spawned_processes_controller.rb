module Admin
  # Subprocess inventory for the admin UI. Every claude / codex /
  # grader / git / prepare command spawned through ProcessRunner
  # shows up here with staleness, timeouts, host metrics, and a
  # Kill button. The Kill button stamps kill_requested_at on the
  # row — the owning worker pod polls that flag and terminates the
  # local pid (cross-pod kill via DB; pids aren't portable).
  class SpawnedProcessesController < BaseController
    PER_PAGE = 50

    def index
      scope = SpawnedProcess.order(started_at: :desc).limit(PER_PAGE * 4)
      scope = apply_state_filter(scope)
      scope = scope.where(kind: params[:kind]) if SpawnedProcess::KINDS.include?(params[:kind])
      scope = scope.where(hostname: params[:hostname]) if params[:hostname].present?
      scope = scope.where(run_id: params[:run_id]) if params[:run_id].present?
      scope = scope.where(workflow_id: params[:workflow_id]) if params[:workflow_id].present?

      @processes = scope.to_a
      @running_count = SpawnedProcess.running.count
      @kinds = SpawnedProcess::KINDS
      @hostnames = SpawnedProcess.where("started_at > ?", 24.hours.ago).distinct.pluck(:hostname).sort
    end

    def show
      @process = SpawnedProcess.find(params[:id])
      @host_metrics = @process.host_metrics
    end

    def kill
      process = SpawnedProcess.find(params[:id])
      if process.finished?
        redirect_to admin_processes_path, alert: "Process ##{process.id} is already finalized (#{process.outcome})."
        return
      end

      process.request_kill!(user: Current.user)
      redirect_to admin_processes_path, notice: "Kill requested for process ##{process.id} (#{process.kind}). Worker will pick it up within ~1s."
    end

    private

    # Defaults to "active or recently finished" — the most useful view
    # for the operator who's debugging right now. ?state=all returns
    # the whole table, ?state=running just live rows, ?state=finished
    # just done rows.
    def apply_state_filter(scope)
      case params[:state]
      when "running"  then scope.running
      when "finished" then scope.finished
      when "all"      then scope
      else
        cutoff = 1.hour.ago
        scope.where("finished_at IS NULL OR finished_at >= ?", cutoff)
      end
    end
  end
end
