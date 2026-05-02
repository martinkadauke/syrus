require "rails_helper"

RSpec.describe Job do
  describe "initial state" do
    it "is queued on create" do
      expect(Factories.job).to be_queued
    end
  end

  describe "legal transitions" do
    it "queued → running via start, sets started_at" do
      job = Factories.job
      freeze_time do
        expect { job.start! }.to change(job, :state).from("queued").to("running")
        expect(job.started_at).to eq(Time.current)
      end
    end

    it "running → succeeded via succeed, sets finished_at" do
      job = Factories.job
      job.start!
      freeze_time do
        expect { job.succeed! }.to change(job, :state).from("running").to("succeeded")
        expect(job.finished_at).to eq(Time.current)
      end
    end

    it "queued → cancelled via cancel" do
      job = Factories.job
      expect { job.cancel! }.to change(job, :state).from("queued").to("cancelled")
      expect(job.finished_at).to be_present
    end

    it "running → cancelled via cancel" do
      job = Factories.job
      job.start!
      expect { job.cancel! }.to change(job, :state).from("running").to("cancelled")
    end

    it "running → failed via fail" do
      job = Factories.job
      job.start!
      expect { job.fail! }.to change(job, :state).from("running").to("failed")
    end

    it "queued → failed via fail (pre-flight failure)" do
      job = Factories.job
      expect { job.fail! }.to change(job, :state).from("queued").to("failed")
    end
  end

  describe "illegal transitions" do
    it "cannot start from a terminal state" do
      job = Factories.job
      job.cancel!
      expect(job.may_start?).to be false
    end

    it "cannot succeed without starting first" do
      job = Factories.job
      expect(job.may_succeed?).to be false
    end

    it "cannot cancel a terminal job" do
      job = Factories.job
      job.start!
      job.succeed!
      expect(job.may_cancel?).to be false
    end
  end

  describe "scopes" do
    it "active includes queued and running" do
      a = Factories.job
      b = Factories.job
      b.start!
      done = Factories.job
      done.cancel!
      expect(Job.active).to contain_exactly(a, b)
    end
  end
end
