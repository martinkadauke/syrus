class WorkEngineReconcilerActivityEvent < ApplicationRecord
  EVENT_TYPES = %w[run_started issues_detected repair_planned repair_executed run_finished run_failed].freeze
  SEVERITIES = %w[info warn error alarm].freeze

  belongs_to :job, optional: true
  belongs_to :workflow, optional: true
  belongs_to :step, optional: true
  belongs_to :run, optional: true

  attribute :details, :json, default: -> { {} }

  before_validation { self.details ||= {} }

  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }
  validates :severity, presence: true, inclusion: { in: SEVERITIES }
  validates :source, :message, :occurred_at, presence: true

  before_update { raise ActiveRecord::ReadOnlyRecord, "WorkEngineReconcilerActivityEvent is append-only" }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "WorkEngineReconcilerActivityEvent is append-only" unless destroyed_by_association }

  scope :recent_first, -> { order(occurred_at: :desc, id: :desc) }

  def self.record!(event_type:, source:, message:, severity: "info", occurred_at: Time.current, job_id: nil, workflow_id: nil, step_id: nil, run_id: nil, issue_kind: nil, repair_action: nil, repair_status: nil, details: {})
    create!(
      event_type: event_type,
      source: source.to_s,
      severity: severity.to_s,
      job_id: job_id,
      workflow_id: workflow_id,
      step_id: step_id,
      run_id: run_id,
      issue_kind: issue_kind&.to_s,
      repair_action: repair_action&.to_s,
      repair_status: repair_status&.to_s,
      message: message.to_s,
      details: JSON.parse(JSON.generate(details || {})),
      occurred_at: occurred_at
    )
  rescue StandardError => e
    Rails.logger.warn("[WorkEngineReconcilerActivityEvent] record failed: #{e.class}: #{e.message}")
    nil
  end
end
