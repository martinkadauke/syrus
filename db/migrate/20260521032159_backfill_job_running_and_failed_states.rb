class BackfillJobRunningAndFailedStates < ActiveRecord::Migration[8.1]
  # Bring existing Jobs into the new :running / :failed state model
  # introduced by the Job AASM expansion. Before this migration:
  #   - :queued was overloaded ("waiting", "actively executing",
  #     "previous attempt failed") and the UI fell back to flaky
  #     current_run.state heuristics to disambiguate.
  #   - :implemented could mean "PR open, idle" or "PR open and a
  #     follow-up workflow (pr_comment / ci_failure) is running."
  #
  # The wire-up in Workflow's start/fail/succeed hooks (Phase 2)
  # transitions newly-instantiated workflows correctly going
  # forward. This migration retroactively backfills existing rows
  # so the new states are immediately accurate everywhere.
  #
  # Idempotent: each UPDATE is a no-op on a second run because the
  # source `state` clause no longer matches once a Job has been
  # advanced. Safe to run multiple times across deploy retries.
  def up
    # :queued Jobs with an active workflow → :running
    execute <<~SQL
      UPDATE jobs SET state = 'running'
      WHERE state = 'queued'
        AND EXISTS (
          SELECT 1 FROM workflows
          WHERE workflows.job_id = jobs.id
            AND workflows.state IN ('queued', 'running')
        )
    SQL

    # :implemented Jobs with an active follow-up workflow (anything
    # except auto_merge, which has its own :landing state) → :running
    execute <<~SQL
      UPDATE jobs SET state = 'running'
      WHERE state = 'implemented'
        AND EXISTS (
          SELECT 1 FROM workflows
          WHERE workflows.job_id = jobs.id
            AND workflows.state IN ('queued', 'running')
            AND workflows.trigger_kind != 'auto_merge'
        )
    SQL

    # :queued Jobs whose attempts have all failed (no active, no
    # succeeded, at least one failed workflow exists) → :failed.
    # Pre-deploy these were the "Retry button is hidden" Jobs.
    execute <<~SQL
      UPDATE jobs SET state = 'failed'
      WHERE state = 'queued'
        AND NOT EXISTS (
          SELECT 1 FROM workflows
          WHERE workflows.job_id = jobs.id
            AND workflows.state IN ('queued', 'running')
        )
        AND NOT EXISTS (
          SELECT 1 FROM workflows
          WHERE workflows.job_id = jobs.id
            AND workflows.state = 'succeeded'
        )
        AND EXISTS (
          SELECT 1 FROM workflows
          WHERE workflows.job_id = jobs.id
            AND workflows.state = 'failed'
        )
    SQL
  end

  # Best-effort revert. Maps the two new states back to :queued —
  # the closest pre-Phase-1 equivalent. Doesn't restore the original
  # state perfectly (some of these rows were never :queued in the
  # source data) but unblocks a rollback without DB-level error.
  def down
    execute "UPDATE jobs SET state = 'queued' WHERE state IN ('running', 'failed')"
  end
end
