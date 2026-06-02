class JobLog < ApplicationRecord
  belongs_to :run

  def self.append!(run:, chunk:, kind: nil)
    text = chunk.to_s
    return nil if text.strip.empty?

    transaction do
      # Lock a fresh Run instance so callers can append even if their
      # in-memory run object has unsaved dirty state from a failed step.
      locked_run = Run.lock.find(run.id)
      next_sequence = (where(run_id: locked_run.id).maximum(:sequence) || -1) + 1
      create!(run: locked_run, chunk: text, sequence: next_sequence, kind: kind)
    end
  end

  validates :chunk, presence: true
  validates :sequence, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :sequence, uniqueness: { scope: :run_id }

  before_update { raise ActiveRecord::ReadOnlyRecord, "JobLog is append-only" }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "JobLog is append-only" unless destroyed_by_association }

end
