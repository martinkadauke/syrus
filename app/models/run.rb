class Run < ApplicationRecord
  include AASM

  TRIGGER_KINDS = %w[ initial pr_comment ci_failure replay manual rebase resume ].freeze

  belongs_to :job
  has_many :job_logs, -> { order(:sequence) }, dependent: :destroy
  has_one :claude_session, dependent: :destroy

  validates :trigger_kind, presence: true, inclusion: { in: TRIGGER_KINDS }

  # Backstop for genuine agent hangs (claude alive but making no
  # progress). Rare in practice — claude almost always streams a chunk
  # at least every few minutes. The reaper's PRIMARY signal is the
  # SolidQueue claim being gone (worker died → claim released by SQ
  # supervisor); this threshold only triggers when the claim is still
  # alive but the agent itself stopped emitting transcript output.
  # 30 min comfortably covers normal long-tool-call gaps (large file
  # reads, broad greps, multi-file edits).
  STALE_HEARTBEAT_THRESHOLD = 30.minutes

  scope :active, -> { where(state: %w[ queued running ]) }
  scope :terminal, -> { where(state: %w[ succeeded failed cancelled ]) }
  scope :ordered, -> { order(:created_at) }

  aasm column: :state, whiny_transitions: false do
    state :queued, initial: true
    state :running, :succeeded, :failed, :cancelled

    event :start do
      transitions from: :queued, to: :running, after: -> { self.started_at = Time.current }
    end

    event :succeed do
      transitions from: :running, to: :succeeded, after: -> { self.finished_at = Time.current }
    end

    event :fail do
      transitions from: [ :queued, :running ], to: :failed, after: -> { self.finished_at = Time.current }
    end

    event :cancel do
      transitions from: [ :queued, :running ], to: :cancelled, after: -> { self.finished_at = Time.current }
    end
  end

  after_create_commit :enqueue_run_job

  # State changes (queued → running → succeeded/failed/cancelled) and
  # field updates (agent_turns, agent_outcome, agent_diff) all need to
  # show up on the Job's show page without requiring the operator to
  # refresh. Broadcasting refreshes to the parent Job's stream means
  # "tell anyone watching this Job to morph itself".
  broadcasts_refreshes_to ->(run) { run.job }
  # Also tell the dashboard's per-user "jobs" stream — Run state
  # changes drive the Job's summary pill and the run-count column.
  broadcasts_refreshes_to ->(run) { [ run.job.user, "jobs" ] }

  def self.average_duration_for(trigger_kind)
    completed = terminal.where(trigger_kind: trigger_kind)
                        .where.not(started_at: nil, finished_at: nil)
    return nil if completed.empty?
    total = completed.sum { |r| r.finished_at - r.started_at }
    (total / completed.size).to_i
  end

  def initial?
    trigger_kind == "initial"
  end

  # Rebase Runs are maintenance attempts on an existing PR's branch —
  # they DON'T progress the Job's state. RunJob takes a different code
  # path for them: skip the closed-Job guard, skip commit_agent_changes
  # (the rebase rewrites history rather than modifying the working
  # tree), force-push-with-lease, and skip the PR-opening step.
  def rebase?
    trigger_kind == "rebase"
  end

  # Resume Runs continue a Claude Code session whose worker died
  # mid-flight. RunJob restores the prior session's JSONL to disk
  # before invoking claude with --resume, and uses Prompts::Resume
  # as the new prompt so claude knows what just happened.
  def resume?
    trigger_kind == "resume"
  end

  def terminal?
    succeeded? || failed? || cancelled?
  end

  private

  def enqueue_run_job
    return if terminal?
    RunJob.perform_later(id)
  end
end
