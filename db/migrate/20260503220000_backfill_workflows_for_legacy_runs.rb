class BackfillWorkflowsForLegacyRuns < ActiveRecord::Migration[8.1]
  # Wrap every existing Run (step_id IS NULL) in a single-step
  # Workflow so the new code path's "every Run has a Step" invariant
  # holds across the historical record. Each legacy Run becomes its
  # own one-step Workflow — we don't try to reconstruct a multi-step
  # implement → summarize → pr_open chain for runs that were
  # executed under the v0 monolithic flow, since the historical Run
  # row already represents the whole burst as a single attempt.
  #
  # The mapping from trigger_kind → step kind picks the kind that
  # most closely matches what that Run was doing:
  #
  #   initial     → implement     (issue → branch → PR)
  #   replay      → implement     (re-run of an initial)
  #   pr_comment  → respond
  #   ci_failure  → analyze_and_fix
  #   rebase      → agent_rebase
  #   manual      → manual
  #   resume      → manual         (continuation; no specific kind)
  #
  # Workflow state derives from the Run's state. Step state ditto.
  # failure_count stays 0 — the per-Workflow cap is forward-looking
  # and shouldn't penalize historical Workflows for prior failures.
  #
  # All work happens via raw SQL through `execute` so the migration
  # doesn't depend on the current Workflow / Step model classes
  # (whose validations / callbacks would fight us during a backfill).
  def up
    legacy_run_rows.each_slice(500) do |slice|
      ActiveRecord::Base.transaction do
        slice.each { |row| backfill_one(row) }
      end
    end
  end

  def down
    # Best-effort reversal: only delete workflows / steps whose sole
    # step wraps exactly one Run (the historical 1:1 wrapper we
    # created above). Modern multi-step Workflows with their own
    # Runs are left alone.
    #
    # Order matters: NULL out the runs' step_id FIRST so the FK
    # constraint passes when we delete the steps.
    execute(<<~SQL)
      UPDATE runs SET step_id = NULL
       WHERE step_id IN (
         SELECT s.id FROM steps s
          INNER JOIN workflows w ON w.id = s.workflow_id
          WHERE w.failure_count = 0
            AND (SELECT COUNT(*) FROM steps WHERE workflow_id = w.id) = 1
            AND (SELECT COUNT(*) FROM runs  WHERE step_id    = s.id) = 1
       )
    SQL
    execute(<<~SQL)
      DELETE FROM steps
       WHERE id NOT IN (SELECT step_id FROM runs WHERE step_id IS NOT NULL)
         AND workflow_id IN (
           SELECT id FROM workflows WHERE failure_count = 0
         )
    SQL
    execute(<<~SQL)
      DELETE FROM workflows
       WHERE id NOT IN (SELECT DISTINCT workflow_id FROM steps)
    SQL
  end

  private

  TRIGGER_TO_STEP_KIND = {
    "initial"    => "implement",
    "replay"     => "implement",
    "pr_comment" => "respond",
    "ci_failure" => "analyze_and_fix",
    "rebase"     => "agent_rebase",
    "manual"     => "manual",
    "resume"     => "manual"
  }.freeze

  def legacy_run_rows
    ActiveRecord::Base.connection.exec_query(<<~SQL).rows
      SELECT id, job_id, trigger_kind, state, started_at, finished_at, created_at
        FROM runs
       WHERE step_id IS NULL
       ORDER BY id
    SQL
  end

  def backfill_one(row)
    run_id, job_id, trigger_kind, state, started_at, finished_at, run_created_at = row

    step_kind = TRIGGER_TO_STEP_KIND[trigger_kind]
    unless step_kind
      Rails.logger.warn("[backfill_workflows] unknown trigger_kind #{trigger_kind.inspect} on Run ##{run_id}; skipping")
      return
    end

    # Workflow's timestamps mirror the Run's so the historical
    # ordering on Job#show stays correct.
    wf_id = ActiveRecord::Base.connection.insert(<<~SQL)
      INSERT INTO workflows (
        job_id, trigger_kind, state, failure_count, artifacts,
        started_at, finished_at, created_at, updated_at
      ) VALUES (
        #{quote_int(job_id)},
        #{quote_str(trigger_kind)},
        #{quote_str(state)},
        0,
        NULL,
        #{quote_ts(started_at)},
        #{quote_ts(finished_at)},
        #{quote_ts(run_created_at)},
        #{quote_ts(run_created_at)}
      )
    SQL

    step_id = ActiveRecord::Base.connection.insert(<<~SQL)
      INSERT INTO steps (
        workflow_id, kind, next_step_id, position, state,
        started_at, finished_at, created_at, updated_at
      ) VALUES (
        #{quote_int(wf_id)},
        #{quote_str(step_kind)},
        NULL,
        0,
        #{quote_str(state)},
        #{quote_ts(started_at)},
        #{quote_ts(finished_at)},
        #{quote_ts(run_created_at)},
        #{quote_ts(run_created_at)}
      )
    SQL

    execute("UPDATE runs SET step_id = #{quote_int(step_id)} WHERE id = #{quote_int(run_id)}")
  end

  def quote_int(v)
    v.nil? ? "NULL" : v.to_i.to_s
  end

  def quote_str(v)
    v.nil? ? "NULL" : ActiveRecord::Base.connection.quote(v.to_s)
  end

  def quote_ts(v)
    v.nil? ? "NULL" : ActiveRecord::Base.connection.quote(v)
  end
end
