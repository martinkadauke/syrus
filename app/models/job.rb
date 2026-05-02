class Job < ApplicationRecord
  include AASM

  belongs_to :user
  belongs_to :repository
  has_many :job_logs, -> { order(:sequence) }, dependent: :destroy

  validates :issue_number, presence: true, numericality: { only_integer: true, greater_than: 0 }

  scope :active, -> { where(state: %w[queued running]) }
  scope :terminal, -> { where(state: %w[succeeded failed cancelled]) }

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
end
