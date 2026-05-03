require "rails_helper"

RSpec.describe ReapStaleRunsJob do
  let(:job) { Factories.job }

  # Build a Run in `running` state with the given heartbeat age.
  # Stale (> 30 min) → reapable. Fresh → leave alone.
  def running_run(heartbeat_age:)
    run = Run.create!(job: Factories.job, trigger_kind: "initial")
    run.update_columns(
      state: "running",
      started_at: heartbeat_age.ago,
      last_heartbeat_at: heartbeat_age.ago
    )
    run
  end

  describe "#perform" do
    it "marks a run with stale heartbeat as failed" do
      run = running_run(heartbeat_age: Run::STALE_HEARTBEAT_THRESHOLD + 5.minutes)
      described_class.perform_now
      expect(run.reload.state).to eq("failed")
    end

    it "sets agent_outcome to worker_died" do
      run = running_run(heartbeat_age: Run::STALE_HEARTBEAT_THRESHOLD + 5.minutes)
      described_class.perform_now
      expect(run.reload.agent_outcome).to eq("worker_died")
    end

    it "sets finished_at" do
      run = running_run(heartbeat_age: Run::STALE_HEARTBEAT_THRESHOLD + 5.minutes)
      freeze_time do
        described_class.perform_now
        expect(run.reload.finished_at).to eq(Time.current)
      end
    end

    it "leaves a freshly-heartbeated run alone (recent chunks)" do
      run = running_run(heartbeat_age: 30.seconds)
      described_class.perform_now
      expect(run.reload.state).to eq("running")
    end

    it "leaves alone a run mid-long-tool-call (heartbeat under threshold)" do
      run = running_run(heartbeat_age: 10.minutes)
      described_class.perform_now
      expect(run.reload.state).to eq("running")
    end

    it "ignores non-running runs even with very old timestamps" do
      run = Run.create!(job: job, trigger_kind: "initial")
      run.update_columns(state: "succeeded", started_at: 1.hour.ago, finished_at: 30.minutes.ago)
      described_class.perform_now
      expect(run.reload.state).to eq("succeeded")
    end

    it "handles worktree cleanup errors without aborting the job" do
      run = running_run(heartbeat_age: Run::STALE_HEARTBEAT_THRESHOLD + 5.minutes)
      allow_any_instance_of(JobWorkspace).to receive(:cleanup).and_raise(RuntimeError, "no such worktree")
      expect { described_class.perform_now }.not_to raise_error
      expect(run.reload.state).to eq("failed")
    end

    it "reaps multiple stale runs in one pass" do
      r1 = running_run(heartbeat_age: Run::STALE_HEARTBEAT_THRESHOLD + 5.minutes)
      r2 = running_run(heartbeat_age: Run::STALE_HEARTBEAT_THRESHOLD + 60.minutes)
      described_class.perform_now
      expect(r1.reload.state).to eq("failed")
      expect(r2.reload.state).to eq("failed")
    end
  end

  describe "Run.stale scope" do
    it "includes a running run whose last_heartbeat_at is past the threshold" do
      run = running_run(heartbeat_age: Run::STALE_HEARTBEAT_THRESHOLD + 1.minute)
      expect(Run.stale).to include(run)
    end

    it "includes a running run with no heartbeat but an old started_at" do
      run = Run.create!(job: job, trigger_kind: "initial")
      run.update_columns(state: "running", started_at: (Run::STALE_HEARTBEAT_THRESHOLD + 1.minute).ago, last_heartbeat_at: nil)
      expect(Run.stale).to include(run)
    end

    it "excludes a running run with a recent heartbeat" do
      run = running_run(heartbeat_age: 30.seconds)
      expect(Run.stale).not_to include(run)
    end

    it "excludes a non-running run regardless of timestamps" do
      run = Run.create!(job: job, trigger_kind: "initial")
      run.update_columns(state: "failed", started_at: 1.hour.ago, finished_at: 30.minutes.ago)
      expect(Run.stale).not_to include(run)
    end
  end
end
