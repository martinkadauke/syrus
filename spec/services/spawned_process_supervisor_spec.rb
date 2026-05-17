require "rails_helper"
require "socket"

RSpec.describe SpawnedProcessSupervisor do
  let(:hostname) { Socket.gethostname }

  def fixture(**overrides)
    SpawnedProcess.create!({
      kind: "agent",
      command: "claude --print",
      hostname: hostname,
      started_at: 1.minute.ago,
      pid: 999_999_999 # vanishingly unlikely to exist
    }.merge(overrides))
  end

  describe ".tick" do
    it "finalizes own-hostname rows whose pid is gone" do
      sp = fixture
      allow(Process).to receive(:kill).with(0, sp.pid).and_raise(Errno::ESRCH)

      described_class.tick

      sp.reload
      expect(sp).to be_finished
      expect(sp.outcome).to eq("orphaned")
      expect(sp.finished_at).to be_present
    end

    it "leaves own-hostname rows whose pid is alive" do
      sp = fixture(pid: Process.pid)

      described_class.tick

      sp.reload
      expect(sp).to be_running
      expect(sp.outcome).to be_nil
    end

    it "skips nil-pid rows (worker is mid-spawn or crashed before pid update)" do
      sp = fixture(pid: nil)
      # Process.kill must NOT be invoked — the row should be excluded
      # by the SQL filter, not the Ruby guard.
      expect(Process).not_to receive(:kill)

      described_class.tick

      sp.reload
      expect(sp).to be_running
    end

    it "ignores rows on a different hostname" do
      sp = fixture(hostname: "some-other-pod")

      described_class.tick

      sp.reload
      expect(sp).to be_running
    end

    it "does not touch already-finished rows" do
      sp = fixture(finished_at: 1.second.ago, outcome: "succeeded", exit_status: 0)

      described_class.tick

      sp.reload
      expect(sp.outcome).to eq("succeeded") # untouched
    end

    it "treats EPERM as alive (different uid namespace, etc.)" do
      sp = fixture
      allow(Process).to receive(:kill).with(0, sp.pid).and_raise(Errno::EPERM)

      described_class.tick

      sp.reload
      expect(sp).to be_running
    end

    it "no-ops if a row was finalized between the SELECT and the UPDATE (lost race)" do
      sp = fixture
      allow(Process).to receive(:kill).with(0, sp.pid).and_raise(Errno::ESRCH)

      # Simulate ProcessRunner winning the race: finalize the row
      # between find_each yielding it and the conditional update.
      allow(SpawnedProcess).to receive(:running).and_call_original
      original_update = SpawnedProcess.method(:where)
      allow(SpawnedProcess).to receive(:where) do |*args|
        # On the WHERE id: ... finished_at: nil chain (the conditional
        # update), pre-finalize the row so update_all returns 0.
        if args.first.is_a?(Hash) && args.first[:id] == sp.id && args.first[:finished_at].nil?
          sp.update!(finished_at: Time.current, outcome: "succeeded", exit_status: 0)
        end
        original_update.call(*args)
      end

      described_class.tick

      sp.reload
      # ProcessRunner's outcome wins; supervisor's update_all returned 0.
      expect(sp.outcome).to eq("succeeded")
    end
  end

  describe ".ensure_running" do
    it "is a no-op in the test environment" do
      # disabled? returns true for Rails.env.test?, so no thread spawns.
      expect { described_class.ensure_running }.not_to raise_error
    end
  end
end
