class PerformanceLogEvent < ApplicationRecord
  include ObservabilityEventRecord

  RETENTION = 6.hours

  attribute :payload, :json, default: -> { {} }

  validates :occurred_at, :event_name, presence: true

  scope :expired, -> { where(occurred_at: ...RETENTION.ago) }

  def self.from_event_hash(event)
    attrs = event.to_h
    {
      occurred_at: parse_event_time(attrs["occurred_at"]) || Time.current,
      app_revision: attrs["app_revision"],
      event_name: attrs["event"],
      request_id: attrs["request_id"],
      method: attrs["method"],
      path: attrs["path"],
      controller: attrs["controller"],
      action: attrs["action"],
      phase: attrs["phase"],
      name: attrs["name"],
      trace_id: attrs["trace_id"],
      sql_fingerprint: attrs["fingerprint"].to_s.safe_byteslice(0, 700).presence,
      duration_ms: attrs["duration_ms"],
      sql_count: attrs["sql_count"],
      sql_duration_ms: attrs["sql_duration_ms"],
      slow_sql_count: attrs["slow_sql_count"],
      payload: attrs,
      created_at: Time.current,
      updated_at: Time.current
    }
  end

  def as_event_hash
    payload.to_h.merge(
      "occurred_at" => occurred_at&.iso8601(6),
      "app_revision" => app_revision,
      "event" => event_name,
      "request_id" => request_id,
      "method" => method,
      "path" => path,
      "controller" => controller,
      "action" => action,
      "phase" => phase,
      "name" => name,
      "trace_id" => trace_id,
      "fingerprint" => sql_fingerprint,
      "duration_ms" => duration_ms,
      "sql_count" => sql_count,
      "sql_duration_ms" => sql_duration_ms,
      "slow_sql_count" => slow_sql_count
    ).compact
  end

  def self.as_recent_event_hashes(limit:)
    recent_first.limit(limit).map(&:as_event_hash)
  end
end
