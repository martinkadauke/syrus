require "rails_helper"

RSpec.describe WorkEngineReconcilerActivityEvent do
  it "records append-only reconciler activity with normalized JSON details" do
    job = Factories.job
    event = described_class.record!(
      event_type: "issues_detected",
      source: "spec",
      severity: "warn",
      job_id: job.id,
      issue_kind: "queued_run_without_queue_claim",
      repair_action: "reenqueue_run",
      message: "Run is queued without a queue claim.",
      details: { affected_ids: { job_ids: [ job.id ] } }
    )

    expect(event).to be_persisted
    expect(event.details).to eq("affected_ids" => { "job_ids" => [ job.id ] })
    expect { event.update!(message: "changed") }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end
end
