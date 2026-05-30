module Admin
  module Queue
    class Payload
      PER_PAGE = 100

      def initialize(params:, user:, per_page: PER_PAGE)
        @params = params
        @user = user
        @per_page = per_page
      end

      def active
        jobs = SolidQueue::Job
          .joins(:claimed_execution)
          .order("solid_queue_claimed_executions.created_at DESC")
          .limit(@per_page)

        { jobs: jobs.map { |job| serialize_job(job, claimed_at: job.claimed_execution&.created_at) } }
      end

      def pending
        base = SolidQueue::Job.joins(:ready_execution)
        jobs = base.order("solid_queue_ready_executions.created_at ASC").limit(@per_page)

        { jobs: jobs.map { |job| serialize_job(job) }, total: base.count }
      end

      def failed
        since = failed_since
        failures = SolidQueue::FailedExecution
          .includes(:job)
          .where("created_at >= ?", since)
          .order(created_at: :desc)
          .limit(@per_page)

        {
          since: since.iso8601,
          failures: failures.map { |failure| serialize_failure(failure) }
        }
      end

      def recurring
        tasks = SolidQueue::RecurringTask.order(:key).map do |task|
          last = SolidQueue::RecurringExecution.where(task_key: task.key).order(run_at: :desc).first
          {
            key: task.key,
            class_name: task.class_name,
            schedule: task.schedule,
            last_run_at: last&.run_at,
            last_finished_at: last && SolidQueue::Job.find_by(id: last.job_id)&.finished_at
          }
        end

        { tasks: tasks }
      end

      def workers
        workers = SolidQueue::Process.where(kind: "Worker").order(:hostname, :pid)
        processes = SolidQueue::Process.order(:kind, :hostname, :pid)

        {
          workers: workers.map { |worker| serialize_worker(worker) },
          all_processes: processes.map { |process| serialize_process(process) }
        }
      end

      private

      attr_reader :params, :user

      def failed_since
        params[:since].present? ? Time.iso8601(params[:since]) : 24.hours.ago
      end

      def serialize_job(job, claimed_at: nil)
        {
          id: job.id,
          class_name: job.class_name,
          queue_name: job.queue_name,
          arguments: job.arguments&.dig("arguments"),
          created_at: job.created_at,
          claimed_at: claimed_at
        }
      end

      def serialize_failure(failure)
        error = failure.error || {}
        {
          id: failure.id,
          created_at: failure.created_at,
          class_name: failure.job&.class_name,
          arguments: failure.job&.arguments&.dig("arguments"),
          exception_class: error["exception_class"],
          message: error["message"]
        }
      end

      def serialize_worker(worker)
        {
          pid: worker.pid,
          hostname: worker.hostname,
          queues: worker.metadata&.dig("queues"),
          threads: worker.metadata&.dig("thread_pool_size"),
          last_heartbeat_at: worker.last_heartbeat_at,
          stale: worker.last_heartbeat_at.nil? || worker.last_heartbeat_at < 2.minutes.ago
        }
      end

      def serialize_process(process)
        {
          kind: process.kind,
          pid: process.pid,
          hostname: process.hostname,
          last_heartbeat_at: process.last_heartbeat_at
        }
      end
    end
  end
end
