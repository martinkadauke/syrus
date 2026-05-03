require "rails_helper"

RSpec.describe ReapStaleRunsJob do
  let(:job) { Factories.job }

  # Build a Run in `running` state with the given heartbeat age.
  def running_run(heartbeat_age: 1.minute)
    run = Run.create!(job: Factories.job, trigger_kind: "initial")
    run.update_columns(
      state: "running",
      started_at: heartbeat_age.ago,
      last_heartbeat_at: heartbeat_age.ago
    )
    run
  end

  # Stub the SolidQueue lookup with a controlled set of "currently
  # claimed" Run ids. SolidQueue tables don't exist in the test DB
  # (test runs single-database), so we replace the helper that reads
  # them. The reaper's logic-under-test is the *decision* given a
  # claim set — the lookup query itself is exercised in production.
  def stub_claimed(*run_ids)
    allow_any_instance_of(described_class)
      .to receive(:active_claimed_run_ids)
      .and_return(run_ids.map(&:to_i).to_set)
  end

  describe "#perform" do
    context "worker died (no live SolidQueue claim)" do
      it "marks the running run as failed" do
        run = running_run(heartbeat_age: 30.seconds)
        stub_claimed
        described_class.perform_now
        expect(run.reload.state).to eq("failed")
      end

      it "sets agent_outcome to worker_died" do
        run = running_run(heartbeat_age: 30.seconds)
        stub_claimed
        described_class.perform_now
        expect(run.reload.agent_outcome).to eq("worker_died")
      end

      it "sets finished_at" do
        run = running_run(heartbeat_age: 30.seconds)
        stub_claimed
        freeze_time do
          described_class.perform_now
          expect(run.reload.finished_at).to eq(Time.current)
        end
      end

      it "reaps even if heartbeat is fresh — claim absence is the dominant signal" do
        run = running_run(heartbeat_age: 5.seconds)
        stub_claimed
        described_class.perform_now
        expect(run.reload.state).to eq("failed")
      end
    end

    context "claim alive but heartbeat stale (genuine hang backstop)" do
      it "reaps when the heartbeat exceeds STALE_HEARTBEAT_THRESHOLD" do
        run = running_run(heartbeat_age: Run::STALE_HEARTBEAT_THRESHOLD + 5.minutes)
        stub_claimed(run.id)
        described_class.perform_now
        expect(run.reload.state).to eq("failed")
      end
    end

    context "claim alive and heartbeat fresh (healthy run)" do
      it "leaves a recently-heartbeated run alone" do
        run = running_run(heartbeat_age: 30.seconds)
        stub_claimed(run.id)
        described_class.perform_now
        expect(run.reload.state).to eq("running")
      end

      it "leaves a run alone whose heartbeat is well under the threshold (e.g. mid-tool-call gap)" do
        run = running_run(heartbeat_age: 10.minutes)
        stub_claimed(run.id)
        described_class.perform_now
        expect(run.reload.state).to eq("running")
      end
    end

    it "ignores non-running runs even with no claim" do
      run = Run.create!(job: job, trigger_kind: "initial")
      run.update_columns(state: "succeeded", started_at: 1.hour.ago, finished_at: 30.minutes.ago)
      stub_claimed
      described_class.perform_now
      expect(run.reload.state).to eq("succeeded")
    end

    it "handles worktree cleanup errors without aborting the job" do
      run = running_run(heartbeat_age: 30.seconds)
      stub_claimed
      allow_any_instance_of(JobWorkspace).to receive(:cleanup).and_raise(RuntimeError, "no such worktree")
      expect { described_class.perform_now }.not_to raise_error
      expect(run.reload.state).to eq("failed")
    end

    it "reaps multiple stale runs in one pass — mixed reasons" do
      r1 = running_run(heartbeat_age: 30.seconds)                              # no-claim → reap
      r2 = running_run(heartbeat_age: Run::STALE_HEARTBEAT_THRESHOLD + 5.minutes)  # claimed but hung → reap
      r3 = running_run(heartbeat_age: 30.seconds)                              # claimed and fresh → keep
      stub_claimed(r2.id, r3.id)
      described_class.perform_now
      expect(r1.reload.state).to eq("failed")
      expect(r2.reload.state).to eq("failed")
      expect(r3.reload.state).to eq("running")
    end
  end
end
