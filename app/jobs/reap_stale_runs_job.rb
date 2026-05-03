class ReapStaleRunsJob < ApplicationJob
  queue_as :default

  # Two reaping signals, in order of confidence:
  #
  # 1. Worker died (high confidence, fast). The Run is in `running`
  #    state but its RunJob no longer has a live SolidQueue claim.
  #    SQ's own supervisor releases claims when the owning process's
  #    heartbeat lapses (~5min default), so by the time we see this,
  #    the worker is definitively gone. Reap immediately.
  #
  # 2. Genuine hang (low confidence, slow). The claim IS still alive
  #    but the Run hasn't logged anything in
  #    Run::STALE_HEARTBEAT_THRESHOLD (30 min). Rare in practice;
  #    claude almost always emits transcript chunks more often than
  #    that. This is the backstop for actual hangs.
  #
  # The previous heuristic (any stale heartbeat → reap) produced
  # frequent false positives because long agent tool-calls (large
  # file reads, broad greps) could legitimately go 2-5 min between
  # transcript chunks. Splitting on the SolidQueue signal cuts
  # false positives to ~zero while keeping fast reap on real death.
  def perform
    claimed_run_ids = active_claimed_run_ids

    Run.where(state: "running").find_each do |run|
      reason = reap_reason_for(run, claimed_run_ids)
      next unless reason
      next unless run.may_fail?

      Rails.logger.info("[ReapStaleRunsJob] Run ##{run.id} reaped: #{reason}")
      run.agent_outcome = "worker_died"
      run.fail!
      run.save!

      begin
        JobWorkspace.new(run).cleanup
      rescue => e
        Rails.logger.warn("[ReapStaleRunsJob] worktree cleanup failed for Run ##{run.id}: #{e.message}")
      end
    end
  end

  private

  # Returns a short string explaining why this Run is reapable, or
  # nil if it isn't.
  def reap_reason_for(run, claimed_run_ids)
    if !claimed_run_ids.include?(run.id)
      "no live SolidQueue claim — worker process is gone"
    elsif heartbeat_stale?(run)
      "claim still alive but no heartbeat in #{Run::STALE_HEARTBEAT_THRESHOLD.inspect}"
    end
  end

  def heartbeat_stale?(run)
    threshold = Run::STALE_HEARTBEAT_THRESHOLD.ago
    last = run.last_heartbeat_at || run.started_at
    last.present? && last < threshold
  end

  # Returns the set of Run ids whose RunJob is currently claimed by
  # a worker (i.e. some process is actively executing perform). One
  # query per reap pass; the typical claimed-jobs set is tiny
  # (bounded by worker thread_pool_size × replica count).
  def active_claimed_run_ids
    SolidQueue::Job.where(class_name: "RunJob")
                   .joins(:claimed_execution)
                   .pluck(:arguments)
                   .filter_map { |args| args&.dig("arguments")&.first }
                   .to_set
  end
end
