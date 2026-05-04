module Admin
  # Admin queue inspector. Surfaces SolidQueue's tables so the
  # operator can spot starvation, pruned-worker zombies, stuck
  # recurring jobs, and ailing workers without dropping into a
  # Rails console. See docs/plans/admin-diagnostics.md (B).
  #
  # All queries are wrapped in a SolidQueue-tables-reachable guard
  # because dev/test runs single-database (no separate queue DB);
  # the page degrades to "queue tables unreachable from this
  # connection" instead of 500ing.
  class QueueController < BaseController
    PER_PAGE = 50

    def index
      redirect_to admin_queue_path("active")
    end

    def show
      @tab = params[:tab].to_s
      @page = [ params.fetch(:page, 1).to_i, 1 ].max

      with_queue_tables do
        case @tab
        when "active"     then load_active
        when "pending"    then load_pending
        when "failed"     then load_failed
        when "recurring"  then load_recurring
        when "workers"    then load_workers
        else
          redirect_to admin_queue_path(tab: "active") and return
        end
      end
    end

    # Fast-path the operator for the most common "things look
    # stuck, just reap them" intervention. Same code path that
    # the recurring ReapStaleRunsJob runs every minute — manual
    # button is for when the recurring job itself is starved.
    def reap_stale_runs
      ReapStaleRunsJob.perform_now
      redirect_to admin_queue_path("active"),
                  notice: "ReapStaleRunsJob ran inline."
    end

    private

    # Wrap the body in a broad rescue so the view never sees an
    # AR error from SQ tables being absent (dev/test single-DB
    # setup) or unreachable. Materialize results inside the rescue
    # via `.to_a` so the lazy AR relation can't leak the exception
    # into the view layer. Sets @queue_unreachable so the view
    # renders a friendly placeholder.
    def with_queue_tables
      yield
    rescue ActiveRecord::StatementInvalid,
           ActiveRecord::ConnectionNotEstablished,
           ActiveRecord::ActiveRecordError => e
      @queue_unreachable = e.message
      Rails.logger.debug("[Admin::Queue] queue tables unreachable: #{e.class}: #{e.message}")
    end

    def load_active
      @active = SolidQueue::Job
        .joins(:claimed_execution)
        .order("solid_queue_claimed_executions.created_at DESC")
        .limit(PER_PAGE)
        .to_a  # materialize — keep the rescue around the query
    end

    def load_pending
      base = SolidQueue::Job.joins(:ready_execution)
      @pending_total = base.count
      @pending = base
        .order("solid_queue_ready_executions.created_at ASC")
        .limit(PER_PAGE)
        .offset((@page - 1) * PER_PAGE)
        .to_a
    end

    def load_failed
      since = params[:since].present? ? Time.iso8601(params[:since]) : 24.hours.ago
      @failed = SolidQueue::FailedExecution
        .includes(:job)
        .where("created_at >= ?", since)
        .order(created_at: :desc)
        .limit(PER_PAGE)
        .to_a
      @failed_since = since
    end

    def load_recurring
      @recurring = SolidQueue::RecurringTask.order(:key).to_a.map do |task|
        last = SolidQueue::RecurringExecution.where(task_key: task.key).order(run_at: :desc).first
        {
          key: task.key,
          class_name: task.class_name,
          schedule: task.schedule,
          last_run_at: last&.run_at,
          last_finished_at: last && SolidQueue::Job.find_by(id: last.job_id)&.finished_at
        }
      end
    end

    def load_workers
      @workers = SolidQueue::Process.where(kind: "Worker").order(:hostname, :pid).to_a
      @processes_all = SolidQueue::Process.order(:kind, :hostname, :pid).to_a
    end
  end
end
