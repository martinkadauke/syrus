require "rails_helper"

RSpec.describe SpawnedProcessPruneJob do
  def fixture(**overrides)
    SpawnedProcess.create!({
      kind: "agent",
      command: "claude --print",
      hostname: "host",
      started_at: 8.days.ago
    }.merge(overrides))
  end

  it "deletes finished rows older than the retention window" do
    old = fixture(finished_at: 8.days.ago, outcome: "succeeded", exit_status: 0)
    fresh = fixture(finished_at: 1.day.ago, outcome: "succeeded", exit_status: 0)
    running = fixture(started_at: 1.minute.ago)

    described_class.perform_now

    expect(SpawnedProcess.where(id: old.id)).to be_empty
    expect(SpawnedProcess.where(id: [ fresh.id, running.id ]).count).to eq(2)
  end
end
