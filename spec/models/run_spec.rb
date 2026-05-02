require "rails_helper"

RSpec.describe Run do
  let(:job) { Factories.job }

  describe "AASM state machine (was Job's)" do
    it "starts queued" do
      expect(job.initial_run).to be_queued
    end

    it "queued → running via start, sets started_at" do
      run = job.initial_run
      freeze_time do
        run.start!
        expect(run.state).to eq("running")
        expect(run.started_at).to eq(Time.current)
      end
    end

    it "running → succeeded via succeed, sets finished_at" do
      run = job.initial_run
      run.start!
      freeze_time do
        run.succeed!
        expect(run.state).to eq("succeeded")
        expect(run.finished_at).to eq(Time.current)
      end
    end

    it "queued → cancelled via cancel" do
      run = job.initial_run
      expect { run.cancel! }.to change(run, :state).from("queued").to("cancelled")
      expect(run.finished_at).to be_present
    end

    it "running → failed via fail" do
      run = job.initial_run
      run.start!
      expect { run.fail! }.to change(run, :state).from("running").to("failed")
    end

    it "queued → failed via fail (pre-flight failure)" do
      run = job.initial_run
      expect { run.fail! }.to change(run, :state).from("queued").to("failed")
    end

    it "cannot succeed without starting" do
      run = job.initial_run
      expect(run.may_succeed?).to be false
    end

    it "cannot cancel a terminal run" do
      run = job.initial_run
      run.start!; run.succeed!
      expect(run.may_cancel?).to be false
    end
  end

  describe "trigger_kind" do
    it "validates inclusion" do
      run = Run.new(job: job, trigger_kind: "weird")
      expect(run).not_to be_valid
    end

    it "exposes #initial?" do
      expect(job.initial_run).to be_initial
    end

    it "is not initial for other triggers" do
      followup = Run.create!(job: job, trigger_kind: "pr_comment")
      expect(followup).not_to be_initial
    end
  end

  describe "scopes" do
    it "active = queued + running" do
      a = job.initial_run
      Run.create!(job: job, trigger_kind: "pr_comment")  # queued
      a.start!; a.save!
      expect(job.runs.active.count).to eq(2)
    end

    it "terminal = succeeded + failed + cancelled" do
      a = job.initial_run
      a.start!; a.succeed!; a.save!
      Run.create!(job: job, trigger_kind: "pr_comment")  # queued, not terminal
      expect(job.runs.terminal.count).to eq(1)
    end
  end

  describe "auto-enqueue RunJob on commit" do
    it "enqueues a RunJob with the new Run's id" do
      job  # force creation outside the expect block so its initial-Run
      # enqueue isn't counted against this assertion
      expect {
        Run.create!(job: job, trigger_kind: "pr_comment")
      }.to have_enqueued_job(RunJob).with { |id| expect(id).to be_a(Integer) }
    end

    it "does not enqueue if the Run is created in a terminal state" do
      job
      expect {
        Run.create!(job: job, trigger_kind: "manual", state: "succeeded")
      }.not_to have_enqueued_job(RunJob)
    end
  end

  describe "#terminal?" do
    it "is false for queued and running" do
      run = job.initial_run
      expect(run).not_to be_terminal
      run.start!
      expect(run).not_to be_terminal
    end

    it "is true for succeeded, failed, cancelled" do
      [ ->(r) { r.start!; r.succeed! }, ->(r) { r.fail! }, ->(r) { r.cancel! } ].each do |drive|
        run = Run.create!(job: Factories.job, trigger_kind: "pr_comment")
        drive.call(run)
        expect(run).to be_terminal
      end
    end
  end
end
