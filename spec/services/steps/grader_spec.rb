require "rails_helper"
require "tmpdir"

RSpec.describe Steps::Grader do
  let(:job) { Factories.job }
  let(:workflow) { job.workflows.last }
  let(:step) do
    Step.create!(
      workflow: workflow,
      kind: "grader",
      position: 99,
      details: {
        "name" => "tests",
        "command" => "ruby -e 'puts \"durable output\"'",
        "required" => true,
        "timeout_minutes" => 1
      }
    )
  end
  let(:run) { step.runs.create!(job: job, trigger_kind: workflow.trigger_kind, state: "running", iteration: step.iteration) }
  let(:handler) { described_class.new(run) }

  around do |example|
    Dir.mktmpdir("syrus-grader") do |dir|
      @ws_path = Pathname.new(dir)
      example.run
    end
  end

  before do
    fake_ws = instance_double(WorkflowWorkspace, setup: nil, path: @ws_path)
    allow(handler).to receive(:workspace).and_return(fake_ws)
  end

  it "writes grader output to the workspace file and durable JobLog rows" do
    handler.call

    details = step.reload.details
    expect(@ws_path.join(details["log_path"]).read).to include("durable output")
    expect(run.reload.job_logs.where(kind: "grade_log").order(:sequence).pluck(:chunk).join).to include("durable output")
  end
end
