require "rails_helper"

RSpec.describe Steps::ForcePush do
  let(:job) { Factories.job }
  let(:workflow) { Workflows::Rebase.instantiate(job: job) }
  let(:step) { workflow.steps.find_by!(kind: "force_push") }
  let(:run) { Run.create!(job: job, step: step, trigger_kind: "rebase") }

  it "skips pushing when deterministic auto-rebase already proved the branch was unchanged" do
    workflow.set_artifact!("auto_rebase_result", {
      "reason" => "rebased",
      "changed" => false,
      "post_sha" => "abc",
      "base_sha" => "base"
    })
    handler = described_class.new(run)

    expect(handler).not_to receive(:workspace)

    handler.call

    expect(run.job_logs.pluck(:chunk).join("\n")).to include("force_push: skipped")
  end
end
