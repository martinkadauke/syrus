require "rails_helper"

RSpec.describe WorkflowActivityEvent do
  it "normalizes event hashes into append-only rows" do
    job = Factories.job_record(state: "queued")
    event = described_class.create!(
      described_class.from_event_hash(
        "event_type" => "landing_queue_changed",
        "source" => "spec",
        "severity" => "warn",
        "job_id" => job.id,
        "reason_key" => "pr_checks_failing",
        "message" => "JOB changed.",
        "metadata" => { before: {}, after: { blocked: true } },
        "occurred_at" => "2026-08-15T04:00:00Z"
      )
    )

    expect(event).to be_persisted
    expect(event.metadata).to eq("before" => {}, "after" => { "blocked" => true })
    expect(event.reason_key).to eq("pr_checks_failing")
    expect { event.update!(message: "changed") }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end
end
