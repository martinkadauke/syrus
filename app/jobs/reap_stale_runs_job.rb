class ReapStaleRunsJob < ApplicationJob
  queue_as :default

  # Reap a Run when its own heartbeat (last_heartbeat_at, bumped by
  # RunJob.log on every transcript chunk) hasn't moved in
  # Run::STALE_HEARTBEAT_THRESHOLD (30 min). That's the only signal
  # we trust, because:
  #
  # - The previous version also consulted SolidQueue claim state
  #   ("no live RunJob claim → worker is gone"). Turns out SQ's
  #   supervisor will prune a worker whose own heartbeat thread
  #   lapses for >5 min, even when the worker process is alive and
  #   the RunJob is still executing — DB contention or GVL
  #   pressure can starve the heartbeat thread under load. When SQ
  #   prunes the live worker, claims are released, and the reaper
  #   marked the Run failed even as transcript chunks kept landing.
  #
  # - last_heartbeat_at, in contrast, is bumped synchronously from
  #   the same code path that does work. If the agent is producing
  #   any output at all, the heartbeat is fresh.
  #
  # 30 min is generous: claude almost always emits a chunk well
  # under that threshold, but long tool-calls (large file reads,
  # broad greps, multi-file edits) can legitimately go 2-5 min
  # between chunks, so anything tighter risks the same false-
  # positive class. The cost of the generous threshold is slow
  # recovery from a true worker death (up to 30 min before reap),
  # which the operator can short-circuit with manual Replay.
  def perform
    Run.stale.find_each do |run|
      next unless run.may_fail?

      Rails.logger.info("[ReapStaleRunsJob] Run ##{run.id} reaped: no heartbeat in #{Run::STALE_HEARTBEAT_THRESHOLD.inspect}")
      run.agent_outcome = "worker_died"
      run.fail!
      run.save!

      begin
        JobWorkspace.new(run).cleanup
      rescue => e
        Rails.logger.warn("[ReapStaleRunsJob] workspace cleanup failed for Run ##{run.id}: #{e.message}")
      end
    end
  end
end
