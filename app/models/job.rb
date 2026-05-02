class Job < ApplicationRecord
  include AASM

  belongs_to :user
  belongs_to :repository
  has_many :runs, -> { order(:created_at) }, dependent: :destroy
  has_many :job_logs, through: :runs

  validates :issue_number, presence: true, numericality: { only_integer: true, greater_than: 0 }

  scope :open_threads, -> { where(state: "open") }
  scope :closed_threads, -> { where(state: "closed") }

  aasm column: :state, whiny_transitions: false do
    state :open, initial: true
    state :closed

    event :close do
      transitions from: :open, to: :closed, after: -> { self.finished_at = Time.current }
    end
  end

  after_create_commit :create_initial_run

  def close_with_reason!(reason)
    update!(closure_reason: reason)
    close!
  end

  # Cancels every active Run on this Job and closes the thread. Used by
  # both the Cancel button (reason: "cancelled") and Restart (reason:
  # "replaced"). Idempotent on already-closed Jobs.
  def cancel_active_runs_and_close!(reason)
    return if closed?
    runs.active.find_each do |run|
      run.cancel! if run.may_cancel?
      run.save!
    end
    close_with_reason!(reason)
  end

  # The most recently created Run on this thread, regardless of state.
  def current_run
    runs.last
  end

  # The very first Run — the one that created the branch and PR.
  def initial_run
    runs.find_by(trigger_kind: "initial")
  end

  def latest_succeeded_run
    runs.where(state: "succeeded").last
  end

  def any_active_run?
    runs.active.exists?
  end

  private

  def create_initial_run
    runs.create!(trigger_kind: "initial")
  end
end
