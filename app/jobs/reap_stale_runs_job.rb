class ReapStaleRunsJob < ApplicationJob
  queue_as :default

  # Two reaping signals, in order of confidence/speed:
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
  # 2. Heartbeat-stale (backstop). The Run's own
  #    `last_heartbeat_at` (bumped by RunJob.log on every transcript
  #    chunk) hasn't moved in Run::STALE_HEARTBEAT_THRESHOLD (30
  #    min). Catches the rare case where the worker is alive but
  #    the agent itself is wedged.
  #
  # Why we don't just use SQ claim state as the primary signal: SQ
  # will prune a *live* worker whose SQ-heartbeat thread starves
  # under DB contention — false-positive class that bit us before
  # PR #50. The signal we trust here is `failed_execution +
  # ProcessPrunedError` specifically, NOT "no live claim." That
  # narrow filter means we only act when SQ has *committed* to the
  # worker being dead.
  def perform
    reap_runs_with_pruned_workers   # fast path
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

    begin
      JobWorkspace.new(run).cleanup
    rescue => e
      Rails.logger.warn("[ReapStaleRunsJob] workspace cleanup failed for Run ##{run.id}: #{e.message}")
    end
  end
end
