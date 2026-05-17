require "rails_helper"
require "socket"

RSpec.describe ReapOrphanedSpawnedProcessesJob do
  let(:hostname) { Socket.gethostname }

  def fixture(**overrides)
    SpawnedProcess.create!({
      kind: "agent",
      command: "claude --print",
      hostname: hostname,
      started_at: 30.minutes.ago,
      last_chunk_at: 20.minutes.ago,
      pid: 999_999_999 # very-likely-nonexistent
    }.merge(overrides))
  end

  it "finalizes stale, hostname-local rows whose pid is gone" do
    stale = fixture

    described_class.perform_now

    stale.reload
    expect(stale).to be_finished
    expect(stale.outcome).to eq("orphaned")
  end

  it "leaves stale rows on a different hostname alone" do
    other = fixture(hostname: "some-other-pod")

    described_class.perform_now

    other.reload
    expect(other).to be_running
  end

  it "leaves still-alive pids alone" do
    alive = fixture(pid: Process.pid)
    described_class.perform_now
    alive.reload
    expect(alive).to be_running
  end

  it "leaves recently-heartbeating rows alone" do
    fresh = fixture(last_chunk_at: 1.minute.ago)
    described_class.perform_now
    fresh.reload
    expect(fresh).to be_running
  end
end
