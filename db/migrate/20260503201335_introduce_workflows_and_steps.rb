class IntroduceWorkflowsAndSteps < ActiveRecord::Migration[8.1]
  # Phase 1 of "Job as execution DAG" (linear v1).
  #
  #   Job   ──┐
  #           ├──< Workflow ──< Step ──< Run
  # (existing)
  #
  # A Job today gets multiple bursts of work over its lifetime —
  # initial issue → PR push, then pr_comment rounds, then maybe
  # ci_failure rounds. Each burst is a Workflow. A Workflow lays
  # out a linear chain of Steps (implement → summarize → pr_open,
  # respond → summarize_amend → push, etc.). Each Step has zero or
  # more Runs — a Run is one *attempt* at executing that step.
  #
  # This migration is additive only:
  #   - Adds workflows + steps tables.
  #   - Adds runs.step_id (nullable) so existing Runs (which still
  #     belong to a Job directly via runs.job_id) keep working.
  #   - Backfill of existing Runs into single-step Workflows is
  #     handled in a follow-up migration so a roll-forward is
  #     decoupled from a roll-back-able schema change.
  #
  # The cleanup migration that drops runs.job_id and runs.trigger_kind
  # comes later, after every code path has been moved off of them.
  def change
    create_table :workflows do |t|
      t.references :job, null: false, foreign_key: true, index: true

      # The trigger that spawned this workflow burst — initial,
      # pr_comment, ci_failure, rebase, replay, manual, resume.
      # Each trigger maps to a different Workflows::* template.
      t.string :trigger_kind, null: false

      # State rollup of the chain. Same shape as Run/Step:
      #   queued | running | succeeded | failed | cancelled
      t.string :state, null: false, default: "queued"

      # Per-Workflow failure cap. A bad ci_failure burst doesn't
      # auto-close the Job if the initial burst was clean.
      t.integer :failure_count, null: false, default: 0

      # Free-form artifacts the agent (or non-agentic step handlers)
      # produce during this workflow — pr_title / pr_body / summary
      # today; test_plan / review_findings / etc. as v3+ ships them.
      # Stored as JSON-on-text so downstream steps can read what
      # upstream produced without us declaring every artifact type
      # in the schema.
      t.text :artifacts

      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps

      t.index [ :job_id, :created_at ]
    end

    create_table :steps do |t|
      t.references :workflow, null: false, foreign_key: true, index: true

      # The kind of work this step does — implement, summarize,
      # pr_open, push, auto_rebase, agent_rebase, force_push,
      # respond, summarize_amend, analyze_and_fix, manual, ...
      # Each kind has a Steps::<Kind> handler that does the actual
      # work; agentic kinds spawn claude, non-agentic kinds run
      # service code.
      t.string :kind, null: false

      # Linear chain — one step points to the next. v3 will replace
      # this with a join table for arbitrary DAGs; v1 stays linear.
      t.bigint :next_step_id

      # Zero-based position in the chain — denormalized for the
      # "step 2 / 3" UI affordance and for cheap ordering.
      t.integer :position, null: false, default: 0

      # State machine — same shape as Run.
      t.string :state, null: false, default: "queued"

      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps

      t.index :next_step_id
      t.index [ :workflow_id, :position ]
    end

    # FK on next_step_id pointing back at the same table — explicit
    # so cycles can't sneak in undetected (we'd see a not-null
    # constraint failure on insert if a circular pointer were
    # attempted).
    add_foreign_key :steps, :steps, column: :next_step_id

    # Runs gain a Step parent. Nullable for now — existing Runs
    # still link to Jobs directly via the existing runs.job_id
    # column. The backfill migration that creates Step rows for
    # existing Runs and populates this column ships separately.
    add_reference :runs, :step, null: true, foreign_key: true, index: true
  end
end
