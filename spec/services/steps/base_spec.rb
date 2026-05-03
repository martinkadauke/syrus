require "rails_helper"

RSpec.describe Steps::Base do
  let(:job)      { Factories.job }
  let(:workflow) { Workflow.create!(job: job, trigger_kind: "initial") }
  let(:step)     { Step.create!(workflow: workflow, kind: "implement", position: 0) }
  let(:run)      do
    Run.create!(job: job, step: step, trigger_kind: "initial").tap { |r| r.start!; r.save! }
  end

  # Concrete subclass so we can exercise Base's helpers without
  # invoking real handlers' git/claude side-effects.
  let(:handler_class) do
    Class.new(described_class) do
      def call; nil; end
      public :log, :parent_session_id   # expose for tests
    end
  end
  let(:handler) { handler_class.new(run) }

  describe "#log" do
    it "appends a JobLog with auto-incremented sequence" do
      handler.log("hello")
      handler.log("world")
      expect(run.job_logs.order(:sequence).pluck(:chunk)).to eq(%w[ hello world ])
    end

    it "skips blank chunks (would otherwise hit JobLog presence validation)" do
      expect { handler.log("") }.not_to change { run.job_logs.count }
      expect { handler.log("   \n\n  ") }.not_to change { run.job_logs.count }
    end

    it "still bumps the heartbeat on blank chunks (sign of life from upstream stream)" do
      run.update_columns(last_heartbeat_at: 1.hour.ago)
      handler.log("")
      expect(run.reload.last_heartbeat_at).to be_within(2.seconds).of(Time.current)
    end
  end

  describe "#cancel_downstream!" do
    let!(:s1) { Step.create!(workflow: workflow, kind: "auto_rebase",  position: 0) }
    let!(:s2) { Step.create!(workflow: workflow, kind: "agent_rebase", position: 1) }
    let!(:s3) { Step.create!(workflow: workflow, kind: "force_push",   position: 2) }
    before do
      s1.update!(next_step_id: s2.id)
      s2.update!(next_step_id: s3.id)
    end

    let(:cancel_run) do
      r = Run.create!(job: job, step: s1, trigger_kind: "rebase")
      r.start!; r.save!
      r
    end

    it "cancels every downstream step in the chain" do
      handler_class.new(cancel_run).send(:cancel_downstream!, reason: "auto-rebased clean")
      expect(s2.reload.state).to eq("cancelled")
      expect(s3.reload.state).to eq("cancelled")
    end

    it "leaves the current step alone (it's still mid-execution)" do
      s1.start!; s1.save!
      handler_class.new(cancel_run).send(:cancel_downstream!)
      expect(s1.reload.state).to eq("running")
    end

    it "is idempotent — already-terminal steps stay as they were" do
      s2.update!(state: "succeeded", started_at: 1.minute.ago, finished_at: Time.current)
      handler_class.new(cancel_run).send(:cancel_downstream!)
      expect(s2.reload.state).to eq("succeeded")
      expect(s3.reload.state).to eq("cancelled")
    end

    it "logs each cancellation with the reason" do
      handler_class.new(cancel_run).send(:cancel_downstream!, reason: "nothing left to do")
      logs = cancel_run.job_logs.pluck(:chunk).join("\n")
      expect(logs).to include("cancelling downstream step ##{s2.id}")
      expect(logs).to include("nothing left to do")
    end
  end

  describe "#parent_session_id resolution" do
    let!(:upstream_step) { Step.create!(workflow: workflow, kind: "implement", position: 0) }
    let!(:current_step)  { Step.create!(workflow: workflow, kind: "summarize", position: 1) }
    before { upstream_step.update!(next_step_id: current_step.id) }

    it "is nil for the first step in a workflow" do
      run = Run.create!(job: job, step: upstream_step, trigger_kind: "initial")
      h = handler_class.new(run)
      expect(h.parent_session_id).to be_nil
    end

    it "is nil when upstream hasn't succeeded yet" do
      run = Run.create!(job: job, step: current_step, trigger_kind: "initial")
      h = handler_class.new(run)
      expect(h.parent_session_id).to be_nil
    end

    it "returns the upstream step's last successful run's session_id" do
      upstream_run = Run.create!(job: job, step: upstream_step, trigger_kind: "initial",
                                  state: "succeeded")
      ClaudeSession.create!(run: upstream_run, session_id: "S-upstream", transcript_jsonl: "x")
      upstream_step.update!(state: "succeeded", started_at: 1.minute.ago, finished_at: Time.current)

      current_run = Run.create!(job: job, step: current_step, trigger_kind: "initial")
      h = handler_class.new(current_run)
      expect(h.parent_session_id).to eq("S-upstream")
    end

    it "an explicit run.parent_session_id wins over the chain (Resume semantics)" do
      run = Run.create!(job: job, step: current_step, trigger_kind: "resume",
                        parent_session_id: "S-explicit")
      h = handler_class.new(run)
      expect(h.parent_session_id).to eq("S-explicit")
    end
  end
end
