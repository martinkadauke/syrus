class RunDiagnostic < ApplicationRecord
  belongs_to :run

  # JSON-on-text columns. Letting Rails serialize keeps the model
  # surface clean (Hash in/out) while leaving the underlying TEXT
  # column easy to inspect via SQL when needed.
  serialize :git_snapshot,         coder: JSON
  serialize :environment_snapshot, coder: JSON
  serialize :repo_snapshot,        coder: JSON

  validates :error_class, presence: true

  # 30 days is generous — failed Runs that get manually retried
  # rarely need their diagnostic past a couple weeks. Bump if it
  # turns out incident triage drags out longer.
  RETAIN_AFTER = 30.days

  scope :prunable, -> {
    where("created_at < ?", RETAIN_AFTER.ago)
  }
end
