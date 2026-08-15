class WorkflowActivityEvent < ApplicationRecord
  include ObservabilityEventRecord

  RETENTION = 14.days

  EVENT_TYPES = %w[
    workflow_created
    workflow_started
    workflow_finished
    run_started
    run_finished
    landing_queue_changed
    landing_workflow_dispatched
  ].freeze
  SEVERITIES = %w[info warn error].freeze

  belongs_to :repository, optional: true
  belongs_to :epic, optional: true
  belongs_to :job, optional: true
  belongs_to :workflow, optional: true
  belongs_to :step, optional: true
  belongs_to :run, optional: true

  attribute :metadata, :json, default: -> { {} }

  validates :occurred_at, :event_type, :source, :severity, :message, presence: true
  validates :event_type, inclusion: { in: EVENT_TYPES }
  validates :severity, inclusion: { in: SEVERITIES }

  before_validation { self.metadata ||= {} }
  before_update { raise ActiveRecord::ReadOnlyRecord, "WorkflowActivityEvent is append-only" }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "WorkflowActivityEvent is append-only" unless destroyed_by_association }

  scope :expired, -> { where(occurred_at: ...RETENTION.ago) }

  def self.from_event_hash(event)
    attrs = event.to_h
    {
      occurred_at: parse_event_time(attrs["occurred_at"]) || Time.current,
      event_type: attrs["event_type"],
      source: attrs["source"],
      severity: attrs["severity"] || "info",
      app_revision: attrs["app_revision"],
      hostname: attrs["hostname"],
      pid: attrs["pid"],
      repository_id: attrs["repository_id"],
      epic_id: attrs["epic_id"],
      job_id: attrs["job_id"],
      workflow_id: attrs["workflow_id"],
      step_id: attrs["step_id"],
      run_id: attrs["run_id"],
      trigger_kind: attrs["trigger_kind"],
      workflow_state: attrs["workflow_state"],
      step_kind: attrs["step_kind"],
      run_state: attrs["run_state"],
      reason_key: attrs["reason_key"],
      duration_ms: attrs["duration_ms"],
      message: attrs["message"],
      metadata: normalized_event_json(attrs["metadata"]),
      created_at: Time.current,
      updated_at: Time.current
    }.compact
  end

  def as_event_hash
    {
      "event" => "syrus.workflow_activity",
      "occurred_at" => occurred_at&.iso8601(6),
      "event_type" => event_type,
      "source" => source,
      "severity" => severity,
      "app_revision" => app_revision,
      "hostname" => hostname,
      "pid" => pid,
      "repository_id" => repository_id,
      "epic_id" => epic_id,
      "job_id" => job_id,
      "workflow_id" => workflow_id,
      "step_id" => step_id,
      "run_id" => run_id,
      "trigger_kind" => trigger_kind,
      "workflow_state" => workflow_state,
      "step_kind" => step_kind,
      "run_state" => run_state,
      "reason_key" => reason_key,
      "duration_ms" => duration_ms,
      "message" => message,
      "metadata" => metadata
    }.compact
  end

  def self.as_recent_event_hashes(limit:)
    recent_first.limit(limit).map(&:as_event_hash)
  end
end
