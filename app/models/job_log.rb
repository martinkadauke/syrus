class JobLog < ApplicationRecord
  belongs_to :run

  validates :chunk, presence: true
  validates :sequence, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :sequence, uniqueness: { scope: :run_id }

  before_update { raise ActiveRecord::ReadOnlyRecord, "JobLog is append-only" }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "JobLog is append-only" unless destroyed_by_association }

  # Append each chunk into the live transcript on the job-detail page.
  # Broadcast via the parent Job's channel so all runs of a job stream
  # into the same DOM container.
  broadcasts_to ->(log) { [ log.run.job, "logs" ] }, inserts_by: :append, target: ->(log) { "run_#{log.run_id}_logs" }
end
