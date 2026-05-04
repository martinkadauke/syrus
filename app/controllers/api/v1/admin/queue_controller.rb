module Api
  module V1
    module Admin
      # Mirror of Admin::QueueController. Same SolidQueue table
      # introspection, JSON shape. All queries wrapped in a
      # rescue around AR errors — dev/test single-DB setups
      # respond with `{ error: { code: "queue_unreachable" } }`
      # instead of 500ing.
      #
      #   GET  /api/v1/admin/queue/active
      #   GET  /api/v1/admin/queue/pending
      #   GET  /api/v1/admin/queue/failed[?since=ISO8601]
      #   GET  /api/v1/admin/queue/recurring
      #   GET  /api/v1/admin/queue/workers
      #   POST /api/v1/admin/queue/reap_stale_runs
      class QueueController < BaseController
        PER_PAGE = 100

        def active
          with_queue_tables do
            jobs = SolidQueue::Job
              .joins(:claimed_execution)
              .order("solid_queue_claimed_executions.created_at DESC")
              .limit(PER_PAGE)
            render json: { jobs: jobs.map { |j| serialize_job(j, claimed_at: j.claimed_execution&.created_at) } }
          end
        end

        def pending
          with_queue_tables do
            base = SolidQueue::Job.joins(:ready_execution)
            jobs = base.order("solid_queue_ready_executions.created_at ASC").limit(PER_PAGE)
            render json: { jobs: jobs.map { |j| serialize_job(j) }, total: base.count }
          end
        end

        def failed
          with_queue_tables do
            since = params[:since].present? ? Time.iso8601(params[:since]) : 24.hours.ago
            failures = SolidQueue::FailedExecution
              .includes(:job)
              .where("created_at >= ?", since)
              .order(created_at: :desc)
              .limit(PER_PAGE)
            render json: {
              since: since.iso8601,
              failures: failures.map { |fe| serialize_failure(fe) }
            }
          end
        end

        def recurring
          with_queue_tables do
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
            render json: { tasks: tasks }
          end
        end

        def workers
          with_queue_tables do
            ws = SolidQueue::Process.where(kind: "Worker").order(:hostname, :pid)
            render json: {
              workers: ws.map { |w| serialize_worker(w) },
              all_processes: SolidQueue::Process.order(:kind, :hostname, :pid).map { |p|
                { kind: p.kind, pid: p.pid, hostname: p.hostname, last_heartbeat_at: p.last_heartbeat_at }
              }
            }
          end
        end

        def reap_stale_runs
          ReapStaleRunsJob.perform_now
          render json: { ok: true, message: "ReapStaleRunsJob ran inline." }
        end

        private

        def with_queue_tables
          yield
        rescue ActiveRecord::StatementInvalid,
               ActiveRecord::ConnectionNotEstablished,
               ActiveRecord::ActiveRecordError => e
          render_error("queue_unreachable",
                       "SolidQueue tables unreachable from this connection: #{e.message}",
                       status: :service_unavailable)
        end

        def serialize_job(j, claimed_at: nil)
          {
            id: j.id,
            class_name: j.class_name,
            queue_name: j.queue_name,
            arguments: j.arguments&.dig("arguments"),
            created_at: j.created_at,
            claimed_at: claimed_at
          }
        end

        def serialize_failure(fe)
          err = fe.error || {}
          {
            id: fe.id,
            created_at: fe.created_at,
            class_name: fe.job&.class_name,
            arguments: fe.job&.arguments&.dig("arguments"),
            exception_class: err["exception_class"],
            message: err["message"]
          }
        end

        def serialize_worker(w)
          {
            pid: w.pid,
            hostname: w.hostname,
            queues: w.metadata&.dig("queues"),
            threads: w.metadata&.dig("thread_pool_size"),
            last_heartbeat_at: w.last_heartbeat_at,
            stale: w.last_heartbeat_at.nil? || w.last_heartbeat_at < 2.minutes.ago
          }
        end
      end
    end
  end
end
