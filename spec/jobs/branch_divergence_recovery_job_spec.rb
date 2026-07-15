require "rails_helper"

RSpec.describe BranchDivergenceRecoveryJob do
  let(:user) { Factories.user }
  let(:repository) { Factories.repository(user: user, owner: "acme", name: "widgets") }
  let(:job) { Factories.job(repository: repository, issue_number: 42, pr_number: 7, state: "failed", branch_name: "syrus/issue-42-1") }
  let(:workflow) { Workflow.create!(job: job, trigger_kind: "retry", agent_provider: "claude", state: "failed") }

  before do
    workflow.set_artifact!("branch_divergence", {
      "branch" => "syrus/issue-42-1",
      "remote_sha" => "remote-sha",
      "local_sha" => "local-sha"
    })
    allow(AppEvents).to receive(:broadcast)
  end

  it "records force-push failures from the worker" do
    allow(BranchDivergenceRecovery).to receive(:force_push!)
      .with(workflow: workflow, user: user)
      .and_return(BranchDivergenceRecovery::Result.new(error: "workspace unavailable"))

    described_class.perform_now(workflow.id, user.id)

    expect(workflow.reload.artifact("branch_divergence_recovery_error")).to include(
      "message" => "workspace unavailable",
      "user_id" => user.id
    )
    expect(AppEvents).to have_received(:broadcast).with(
      user: job.user,
      type: "updated",
      resource: "job",
      id: job.id,
      changed: [ "workflows", "runs", "state" ]
    )
  end

  it "broadcasts after successful recovery" do
    allow(BranchDivergenceRecovery).to receive(:force_push!)
      .with(workflow: workflow, user: user)
      .and_return(BranchDivergenceRecovery::Result.new(error: nil))

    described_class.perform_now(workflow.id, user.id)

    expect(workflow.reload.artifact("branch_divergence_recovery_error")).to be_nil
    expect(AppEvents).to have_received(:broadcast).with(
      user: job.user,
      type: "updated",
      resource: "job",
      id: job.id,
      changed: [ "workflows", "runs", "state" ]
    )
  end
end
