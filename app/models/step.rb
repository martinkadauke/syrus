class Step < ApplicationRecord
  include AASM

  # The full v1 set. Each kind has a Steps::<Camelized> handler.
  KINDS = %w[
    implement
    summarize
    pr_open
    respond
    summarize_amend
    push
    analyze_and_fix
    auto_rebase
    agent_rebase
    force_push
    manual
  ].freeze

  # Step kinds that spawn a claude subprocess. Non-agentic steps
  # (pr_open, push, auto_rebase, force_push) just run service code
  # — Steps::PrOpen calls PullRequestOpener, Steps::Push runs `git
  # push`, etc. — and never invoke an agent.
  AGENTIC_KINDS = %w[
    implement summarize respond summarize_amend
    analyze_and_fix agent_rebase manual
  ].freeze

  belongs_to :workflow
  belongs_to :next_step, class_name: "Step", optional: true
  has_one :previous_step, class_name: "Step", foreign_key: :next_step_id
  has_many :runs, -> { order(:created_at) }, dependent: :destroy

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :active, -> { where(state: %w[ queued running ]) }
  scope :terminal, -> { where(state: %w[ succeeded failed cancelled ]) }

  aasm column: :state, whiny_transitions: false do
    state :queued, initial: true
    state :running, :succeeded, :failed, :cancelled

    event :start do
      transitions from: :queued, to: :running, after: -> { self.started_at ||= Time.current }
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

  def agentic?
    AGENTIC_KINDS.include?(kind)
  end

  def terminal?
    succeeded? || failed? || cancelled?
  end

  # When a Step succeeds, hand off to the dispatcher to start the
  # next one (if any). Linear chain — `next_step` is at most one.
  # The dispatcher is what creates the Run on the next Step; this
  # callback just signals "I'm done; move along".
  after_update_commit :advance_next_step!, if: :saved_change_to_state_to_succeeded?

  def saved_change_to_state_to_succeeded?
    saved_change_to_state? && state == "succeeded"
  end

  def advance_next_step!
    StepDispatcher.advance_from(self)
  end

  # The most recently created Run on this Step — i.e. the latest
  # attempt. Failed retries become previous Runs; the latest Run
  # is what reflects the step's current state.
  def latest_run
    runs.order(:created_at).last
  end

  # The session_id from the latest succeeded Run on the upstream
  # step, used by this Step's Run as `parent_session_id` so the
  # next claude call resumes the prior conversation. Nil when
  # there's no upstream session (first step in workflow, or
  # cross-workflow trigger).
  def upstream_session_id
    return nil unless previous_step&.state == "succeeded"
    previous_step.latest_run&.claude_session&.session_id
  end
end
