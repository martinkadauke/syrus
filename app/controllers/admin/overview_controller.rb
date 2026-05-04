module Admin
  # Single-page system overview — "is anything wrong?" answered
  # at a glance. Tile-shaped: each tile reports a metric with a
  # color cue and links into the deeper view that explains it.
  # See docs/plans/admin-diagnostics.md (F).
  #
  # The page polls itself every POLL_INTERVAL_SECONDS via the
  # split-button-style Stimulus controller (turbo-morph visit, so
  # expanded details + scroll position survive). Polling beats
  # broadcasting here because we want a stable refresh rhythm,
  # not a per-row event storm — see the rationale in the queue
  # inspector commit.
  class OverviewController < BaseController
    POLL_INTERVAL_SECONDS = 30

    def show
      @poll_interval = POLL_INTERVAL_SECONDS

      @active_runs_total      = Run.where(state: "running").count
      @active_runs_by_trigger = Run.where(state: "running").group(:trigger_kind).count

      @queued_runs_total      = Run.where(state: "queued").count

      @workers_total = 0
      @workers_stale = 0
      @workers_unreachable = false
      with_queue_tables do
        @workers_total = SolidQueue::Process.where(kind: "Worker").count
        @workers_stale = SolidQueue::Process.where(kind: "Worker")
                                            .where("last_heartbeat_at < ?", 2.minutes.ago)
                                            .count
      end

      @recurring_overdue = []
      with_queue_tables do
        SolidQueue::RecurringTask.find_each do |task|
          last = SolidQueue::RecurringExecution.where(task_key: task.key)
                                               .order(run_at: :desc).first
          age = last ? (Time.current - last.run_at) : Float::INFINITY
          # "Overdue" = haven't fired in 5min for sub-minute schedules,
          # 30min for the daily ones. Coarse heuristic: 10min over the
          # task's claimed interval. We don't parse cron here — just
          # flag tasks that haven't run in the last 10 minutes (or
          # never at all). Tunable as we learn what's noisy.
          @recurring_overdue << { key: task.key, age_seconds: age } if age > 10.minutes
        end
      end

      @recent_failures_24h    = Run.where(state: "failed").where("finished_at >= ?", 24.hours.ago).count
      @recent_failures_by_kind = Run.where(state: "failed")
                                    .where("finished_at >= ?", 24.hours.ago)
                                    .group(:trigger_kind).count

      # Per-user GH rate limit signal. Surface anyone < 10% of cap;
      # don't overwhelm the tile with healthy users.
      @gh_low_users = User.where("gh_rate_limit_remaining IS NOT NULL AND gh_rate_limit_limit > 0")
                          .select { |u| u.gh_rate_limit_remaining.to_f / u.gh_rate_limit_limit < 0.10 }

      # ClaudeSession capture rate — succeeded agentic Runs in the
      # last 24h, with vs without a ClaudeSession. The path-encoding
      # bug would have shown 0% here (every implement Run completed
      # but no session was captured). This tile is the canary.
      agentic_kinds = Step::AGENTIC_KINDS
      recent_agentic = Run.joins(:step)
                          .where(steps: { kind: agentic_kinds })
                          .where(runs: { state: "succeeded" })
                          .where("runs.finished_at >= ?", 24.hours.ago)
      @capture_total = recent_agentic.count
      @capture_with_session = recent_agentic.left_outer_joins(:claude_session)
                                            .where.not(claude_sessions: { id: nil })
                                            .count
      @capture_rate = @capture_total.zero? ? nil : (@capture_with_session.to_f / @capture_total)

      # Stuck-things watchlist — anything that should self-heal but
      # hasn't. Keep this list bounded; if it grows past a screen,
      # break out into the dedicated /admin/stuck view (G).
      @stuck = []
      Run.where(state: "running")
         .where("last_heartbeat_at IS NOT NULL AND last_heartbeat_at < ?", Run::STALE_HEARTBEAT_THRESHOLD.ago)
         .find_each do |r|
        @stuck << { kind: :stale_heartbeat, run_id: r.id, job_id: r.job_id,
                    detail: "Run ##{r.id} heartbeat age: #{((Time.current - r.last_heartbeat_at) / 60).to_i}m" }
      end
      Workflow.where(state: "failed")
              .where(cleaned_up_at: nil)
              .where("finished_at < ?", (WorkflowWorkspacePruneJob::RETAIN_AFTER_TERMINAL - 1.day).ago)
              .find_each do |wf|
        @stuck << { kind: :nearly_pruned, workflow_id: wf.id, job_id: wf.job_id,
                    detail: "Workflow ##{wf.id} (#{wf.trigger_kind}) failed #{((Time.current - wf.finished_at) / 86400).to_i}d ago — about to be pruned" }
      end
    end

    private

    def with_queue_tables
      yield
    rescue ActiveRecord::StatementInvalid,
           ActiveRecord::ConnectionNotEstablished,
           ActiveRecord::ActiveRecordError
      @workers_unreachable = true
    end
  end
end
