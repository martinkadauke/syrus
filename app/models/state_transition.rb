class StateTransition < ApplicationRecord
  # Subject is one of Job / Workflow / Step / Run. Polymorphic
  # because the audit shape is uniform across all four — same
  # questions about every record (when did it move, why, who).
  belongs_to :subject, polymorphic: true
  belongs_to :user, optional: true
  belongs_to :run, optional: true

  SOURCES = %w[
    aasm
    propagate
    reconciler
    operator
    system
  ].freeze

  validates :from_state, :to_state, :source, presence: true
  validates :source, inclusion: { in: SOURCES }

  # Seed an empty hash on new records — MySQL 8 disallows defaults
  # on JSON columns, so the migration left the column nullable.
  # SmartFolder + Whiteboard + Step.details use the same pattern.
  after_initialize :default_metadata, if: :new_record?

  scope :for_subject, ->(subject) {
    where(subject_type: subject.class.polymorphic_name, subject_id: subject.id)
  }
  scope :recent, -> { order(created_at: :desc) }

  # Run a block with a specific source tag. Any AASM transition that
  # fires inside the block records this source instead of the default
  # "aasm" — propagation hooks, the reconciler, and operator controllers
  # use this to annotate their lifts.
  def self.with_source(source, user: nil)
    source = source.to_s
    raise ArgumentError, "unknown source: #{source}" unless SOURCES.include?(source)

    prior_source = Thread.current[:state_transition_source]
    prior_user   = Thread.current[:state_transition_user]
    Thread.current[:state_transition_source] = source
    Thread.current[:state_transition_user]   = user
    yield
  ensure
    Thread.current[:state_transition_source] = prior_source
    Thread.current[:state_transition_user]   = prior_user
  end

  def self.current_source
    Thread.current[:state_transition_source] || "aasm"
  end

  def self.current_user
    Thread.current[:state_transition_user]
  end

  # Captured by Concerns::RecordsStateTransitions for any in-flight
  # Run set by RunJob — gives us the "which Run was active when this
  # propagation happened" cross-link.
  def self.current_run_id
    Thread.current[:syrus_current_run]&.id
  end

  private

  def default_metadata
    self.metadata ||= {}
  end
end
