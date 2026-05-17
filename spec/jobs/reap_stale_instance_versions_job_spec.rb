require "rails_helper"

RSpec.describe ReapStaleInstanceVersionsJob do
  def fixture(**overrides)
    InstanceVersion.create!({
      hostname: "syrus-web-abc",
      role: "web",
      version: "abc1234",
      started_at: 1.minute.ago,
      last_heartbeat_at: 5.seconds.ago
    }.merge(overrides))
  end

  it "finalizes rows whose heartbeat is past the reaper threshold" do
    stale = fixture(hostname: "syrus-web-dead", last_heartbeat_at: 10.minutes.ago)

    described_class.perform_now

    stale.reload
    expect(stale).to be_finished
    expect(stale.outcome).to eq("stale")
    expect(stale.finished_at).to be_within(2.seconds).of(stale.last_heartbeat_at)
  end

  it "leaves fresh rows alone" do
    fresh = fixture(last_heartbeat_at: 10.seconds.ago)

    described_class.perform_now

    fresh.reload
    expect(fresh).to be_running
  end

  it "finalizes a row that registered but never heartbeated past the threshold" do
    stuck = fixture(last_heartbeat_at: nil, started_at: 15.minutes.ago)

    described_class.perform_now

    stuck.reload
    expect(stuck).to be_finished
    expect(stuck.outcome).to eq("stale")
  end

  it "does not touch already-finished rows (lost race)" do
    sp = fixture(last_heartbeat_at: 10.minutes.ago, finished_at: 5.minutes.ago, outcome: "shutdown")

    described_class.perform_now

    sp.reload
    expect(sp.outcome).to eq("shutdown") # untouched
  end
end
