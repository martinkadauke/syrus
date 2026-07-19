require "rails_helper"

RSpec.describe Steps::TestPlan do
  let(:user) { Factories.user }
  let(:repository) { Factories.repository(user: user) }
  let(:job) { Factories.job(repository: repository) }
  let(:workflow) { Workflows::Initial.instantiate(job: job) }
  let(:implement_step) { workflow.steps.find_by!(kind: "implement") }
  let!(:implement_run) do
    Run.create!(job: job, step: implement_step, trigger_kind: "initial", state: "succeeded", started_at: 1.minute.ago, finished_at: Time.current)
  end
  let(:test_plan_step) { workflow.steps.find_by!(kind: "test_plan") }
  let(:run) do
    Run.create!(job: job, step: test_plan_step, trigger_kind: "initial").tap { |r| r.start!; r.save! }
  end
  let(:handler) { described_class.new(run) }

  before do
    fake_ws = instance_double(WorkflowWorkspace, setup: true, path: Pathname.new("/tmp/workspace"))
    allow(handler).to receive(:workspace).and_return(fake_ws)
  end

  it "skips the agent call when the implement step already called submit_test_plan" do
    workflow.set_artifact!("test_plan", { steps: [ "Run bin/rspec" ], notes: nil })

    expect(handler).not_to receive(:run_agent)
    handler.call
  end

  it "skips before requiring an implement session when the test plan is already submitted" do
    implement_run.destroy!
    workflow.set_artifact!("test_plan", { steps: [ "Run bin/rspec" ], notes: nil })

    expect(handler).not_to receive(:run_agent)
    expect { handler.call }.not_to raise_error
  end

  it "sets the test-plan prompt, invokes the agent with a short turn budget, and verifies the artifact" do
    expect(handler).to receive(:run_agent) do |prompt:, max_turns:, required_mcp_tools:|
      expect(prompt).to include("submit_test_plan")
      expect(max_turns).to eq(described_class::TEST_PLAN_TURN_BUDGET)
      expect(required_mcp_tools).to eq(%w[submit_test_plan])
      workflow.set_artifact!("test_plan", { steps: [ "Run bin/rspec" ], notes: nil })
    end

    handler.call

    expect(run.reload.prompt).to include("submit_test_plan")
  end

  it "raises StepFailed when the agent does not call submit_test_plan" do
    allow(handler).to receive(:run_agent)

    expect { handler.call }.to raise_error(Steps::Base::StepFailed, /didn't call submit_test_plan/)
  end

  it "writes a fallback test plan when the MCP sidecar is unavailable" do
    allow(handler).to receive(:run_agent).and_raise(Steps::Base::StepFailed, "agent reported mcp_sidecar_failed")

    expect { handler.call }.not_to raise_error

    artifact = workflow.reload.artifact("test_plan")
    expect(artifact["steps"]).to include("Review the PR diff and summary for the intended behavior.")
    expect(artifact["steps"]).to include("Run the required Syrus graders for this repository.")
    expect(artifact["notes"]).to include("MCP sidecar was unavailable")
  end

  it "includes materialized grader commands in the fallback test plan" do
    Step.create!(
      workflow: workflow,
      kind: "grader",
      position: test_plan_step.position,
      state: "succeeded",
      details: {
        "name" => "rspec",
        "command" => "bundle exec rspec",
        "required" => true
      }
    )
    allow(handler).to receive(:run_agent).and_raise(Steps::Base::StepFailed, "agent reported mcp_sidecar_failed")

    handler.call

    expect(workflow.reload.artifact("test_plan")["steps"]).to include("Run rspec: `bundle exec rspec`")
  end

  it "resumes from the succeeded implement session" do
    ClaudeSession.create!(resumable: implement_run, session_id: "implement-thread", transcript_jsonl: "{}\n")

    handler.singleton_class.send(:public, :parent_session_id)

    expect(handler.parent_session_id).to eq("implement-thread")
  end

  context "for coding handoff workflows" do
    let(:workflow) do
      Workflow.create!(
        job: job,
        trigger_kind: "coding_handoff",
        artifacts: { "test_plan" => { "steps" => [], "notes" => nil } }
      )
    end
    let!(:implement_run) { nil }
    let(:test_plan_step) { Step.create!(workflow: workflow, kind: "test_plan", position: 0) }

    it "uses captured artifacts instead of invoking a fresh test-plan agent" do
      expect(handler).not_to receive(:run_agent)

      handler.call
    end

    it "fails loudly if the coding handoff did not capture test-plan artifacts" do
      workflow.update!(artifacts: {})

      expect(handler).not_to receive(:run_agent)
      expect {
        handler.call
      }.to raise_error(Steps::Base::StepFailed, /missing coding handoff test plan artifacts/)
    end
  end
end
