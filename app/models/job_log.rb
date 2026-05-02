class JobLog < ApplicationRecord
  belongs_to :job

  validates :chunk, presence: true
  validates :sequence, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :sequence, uniqueness: { scope: :job_id }

  before_update { raise ActiveRecord::ReadOnlyRecord, "JobLog is append-only" }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "JobLog is append-only" unless destroyed_by_association }

  # Append each chunk into the live transcript on the job-detail page.
  broadcasts_to ->(log) { [ log.job, "logs" ] }, inserts_by: :append, target: "job_logs"
end
