class ReapStaleRunsJob < ApplicationJob
  include SkipIfPending

  queue_as :default

  # Three reaping signals, in order of confidence/speed:
  #
  # 1. SolidQueue itself proved the worker died — the SQ::Job for
  #    this Run is in failed_execution with a `ProcessPrunedError`.
  #    SQ's supervisor doesn't fail-claimed-executions casually:
  #    only after the owning worker process's heartbeat lapsed past
  #    `process_alive_threshold` (5 min default). When we see this,
  #    the worker process is *definitively* gone and so any RunJob
  #    code mid-perform on its behalf is gone too. Reap immediately.
  #    Recovers post-deploy zombies in ~1 min.
  #
  # 2. Orphaned-Run detection — Run is :running but no SQ::Job
  #    exists for it (not pending, not claimed, not failed). This is
  #    the wedge that bit Job 360: RunJob's handle_failure raised on
  #    a dirty-attribute save retry, SQ recorded that as a clean
  #    finish (job row finished_at set, no failed_execution row),
  #    and the Run sat at :running orphaned. With no SQ::Job
  #    referencing the Run, there's no worker that can ever resume
  #    it; reap on the next pass. Grace period of 2 min for the
  #    "Run just created, SQ::Job not yet committed" race.
  #
  # 3. Heartbeat-stale (backstop). The Run's own
  #    `last_heartbeat_at` (bumped by RunJob.log on every transcript
  #    chunk) hasn't moved in Run::STALE_HEARTBEAT_THRESHOLD (30
  #    min). Catches the rare case where the worker is alive but
  #    the agent itself is wedged.
  #
  # Why we don't just use SQ claim state as the primary signal: SQ
  # will prune a *live* worker whose SQ-heartbeat thread starves
  # under DB contention — false-positive class that bit us before
  # PR #50. The signal we trust in path 1 is
  # `failed_execution + ProcessPrunedError` specifically, NOT "no
  # live claim." Path 2 uses a different signal — *no* SQ::Job at
  # all for the Run — which is unambiguous: a Run that's
  # :running with no enqueued/active job is by definition
  # orphaned.
  ORPHAN_RUN_GRACE_PERIOD = 2.minutes

  def perform
    reap_runs_with_pruned_workers   # fast path
    reap_orphaned_running_runs      # ~3-min path
    reap_runs_with_stale_heartbeat  # 30-min backstop
  end

  private

  # Find SolidQueue::Jobs for class_name=RunJob whose only execution
  # row is a failed_execution carrying a ProcessPrunedError. Pull
  # the Run id out of the active_job arguments and reap each
  # matching Run.
  #
  # The error is JSON-serialized in the failed_executions.error
  # column, so we LIKE-match the exception_class string. Portable
  # across SQLite dev/test and MySQL prod (no JSON-column dialect
  # required).
  def reap_runs_with_pruned_workers
    run_ids = pruned_run_ids_from_solid_queue
    return if run_ids.empty?
    Run.where(id: run_ids, state: "running").find_each do |run|
      reap!(run, reason: "SolidQueue::ProcessPrunedError — worker process is gone (deploy or crash)")
    end
  end

  def reap_runs_with_stale_heartbeat
    Run.stale.find_each do |run|
      reap!(run, reason: "no heartbeat in #{Run::STALE_HEARTBEAT_THRESHOLD.inspect}")
    end
  end

  # Finds Runs in :running state with no active SQ::Job referencing
  # them. "Active" here means a row in solid_queue_jobs that hasn't
  # been finalized (finished_at NULL). A pending job, a claimed
  # job, or a failed-but-not-yet-cleaned-up job all qualify;
  # successfully-finished jobs do not. If no row matches, the Run
  # has no worker that will ever resume it — reap it.
  #
  # Grace period (ORPHAN_RUN_GRACE_PERIOD) prevents reaping a Run
  # whose RunJob enqueue hasn't committed yet (the AR transaction
  # creating the Run and enqueuing the SQ::Job can briefly leave
  # the Run visible before the SQ::Job is).
  def reap_orphaned_running_runs
    cutoff = ORPHAN_RUN_GRACE_PERIOD.ago
    candidates = Run.where(state: "running").where("started_at < ?", cutoff).to_a
    return if candidates.empty?

    active_ids = active_run_job_run_ids
    candidates.each do |run|
      next if active_ids.include?(run.id)
      reap!(run, reason: "no SolidQueue::Job for Run ##{run.id} — orphaned (RunJob died without transitioning)")
    end
  rescue ActiveRecord::StatementInvalid => e
    Rails.logger.debug("[ReapStaleRunsJob] SolidQueue tables unreachable (#{e.class}); skipping orphan-run path")
  end

  # Returns the set of Run ids referenced by any non-finalized
  # SQ::Job for class_name=RunJob. Plain pluck + Ruby filter — the
  # active set is small (zero to a few dozen Runs at any moment),
  # so the cost is bounded.
  def active_run_job_run_ids
    SolidQueue::Job
      .where(class_name: "RunJob", finished_at: nil)
      .pluck(:arguments)
      .filter_map { |args| args&.dig("arguments")&.first }
      .map(&:to_i)
      .to_set
  end

  # Returns the set of Run ids whose RunJob's SQ::Job has a
  # `failed_execution` whose error string includes
  # `ProcessPrunedError`. One join + one LIKE per pass. The
  # filtered result set is bounded by "Runs whose worker died
  # since the last reap" — usually 0, occasionally a small batch
  # right after a deploy.
  def pruned_run_ids_from_solid_queue
    SolidQueue::Job
      .where(class_name: "RunJob")
      .joins(:failed_execution)
      .where("solid_queue_failed_executions.error LIKE ?", "%ProcessPrunedError%")
      .pluck(:arguments)
      .filter_map { |args| args&.dig("arguments")&.first }
      .map(&:to_i)
      .uniq
  rescue ActiveRecord::StatementInvalid => e
    # The SolidQueue tables aren't reachable from this connection
    # — local dev/test runs single-database, so the queue tables
    # don't exist there. Heartbeat-stale path still covers this.
    Rails.logger.debug("[ReapStaleRunsJob] SolidQueue tables unreachable (#{e.class}); skipping pruned-worker fast path")
    []
  end

  def reap!(run, reason:)
    return unless run.may_fail?

    Rails.logger.info("[ReapStaleRunsJob] Run ##{run.id} reaped: #{reason}")
    run.agent_outcome = "worker_died"
    run.fail!
    run.save!

    # Workflow's terminal-state callback handles workspace teardown
    # on its own when Run.fail above triggers Step.fail (via Step's
    # after_update_commit) which triggers Workflow.fail. The reaper
    # only needs to make sure the Run+Step both transition.
    if run.step && run.step.may_fail?
      run.step.fail!
      run.step.save!
    end
  rescue StandardError => e
    Rails.logger.warn("[ReapStaleRunsJob] reap failed for Run ##{run.id}: #{e.class}: #{e.message}")
  end
end
