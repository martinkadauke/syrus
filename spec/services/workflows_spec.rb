require "rails_helper"

RSpec.describe Workflows do
  let(:job) { Factories.job }

  describe ".for(trigger_kind:)" do
    it "returns the right template class for each known trigger_kind" do
      expect(described_class.for(trigger_kind: "initial")).to    eq(Workflows::Initial)
      expect(described_class.for(trigger_kind: "pr_comment")).to eq(Workflows::PrFeedback)
      expect(described_class.for(trigger_kind: "ci_failure")).to eq(Workflows::CiFailure)
      expect(described_class.for(trigger_kind: "rebase")).to     eq(Workflows::Rebase)
      expect(described_class.for(trigger_kind: "replay")).to     eq(Workflows::Replay)
      expect(described_class.for(trigger_kind: "manual")).to     eq(Workflows::Manual)
      expect(described_class.for(trigger_kind: "resume")).to     eq(Workflows::Resume)
    end

    it "raises on an unknown trigger_kind" do
      expect { described_class.for(trigger_kind: "bogus") }.to raise_error(ArgumentError, /trigger_kind/)
    end

    it "accepts a Symbol as well as a String (denormalization)" do
      expect(described_class.for(trigger_kind: :initial)).to eq(Workflows::Initial)
    end
  end

  describe ".instantiate(job:)" do
    it "creates the workflow + chain for Initial in transaction" do
      wf = Workflows::Initial.instantiate(job: job)
      expect(wf).to be_persisted
      expect(wf.trigger_kind).to eq("initial")
      expect(wf.state).to eq("queued")
      expect(wf.steps.pluck(:kind, :position)).to eq([
        [ "implement", 0 ], [ "summarize", 1 ], [ "pr_open", 2 ]
      ])
    end

    it "wires next_step_id top-down (linear chain)" do
      wf = Workflows::Initial.instantiate(job: job)
      a, b, c = wf.steps.order(:position)
      expect(a.next_step).to eq(b)
      expect(b.next_step).to eq(c)
      expect(c.next_step).to be_nil
    end

    it "instantiates PrFeedback with respond → summarize_amend → push" do
      wf = Workflows::PrFeedback.instantiate(job: job)
      expect(wf.steps.pluck(:kind)).to eq(%w[ respond summarize_amend push ])
    end

    it "instantiates CiFailure with analyze_and_fix → summarize_amend → push" do
      wf = Workflows::CiFailure.instantiate(job: job)
      expect(wf.steps.pluck(:kind)).to eq(%w[ analyze_and_fix summarize_amend push ])
    end

    it "instantiates Rebase with auto_rebase → agent_rebase → force_push" do
      wf = Workflows::Rebase.instantiate(job: job)
      expect(wf.steps.pluck(:kind)).to eq(%w[ auto_rebase agent_rebase force_push ])
    end

    it "instantiates Manual with a single 'manual' step" do
      wf = Workflows::Manual.instantiate(job: job)
      expect(wf.steps.pluck(:kind)).to eq(%w[ manual ])
      expect(wf.steps.first.next_step).to be_nil
    end

    it "instantiates Resume with a single 'manual' step (continuation via --resume)" do
      wf = Workflows::Resume.instantiate(job: job)
      expect(wf.steps.pluck(:kind)).to eq(%w[ manual ])
    end

    it "rolls back the workflow + steps if any step creation fails" do
      allow(Step).to receive(:create!).and_call_original
      allow(Step).to receive(:create!).with(hash_including(kind: "pr_open"))
                                      .and_raise(ActiveRecord::RecordInvalid.new(Step.new))

      expect { Workflows::Initial.instantiate(job: job) }
        .to raise_error(ActiveRecord::RecordInvalid)

      expect(Workflow.where(job: job)).to be_empty
      expect(Step.where(kind: "implement")).to be_empty
    end
  end
end
