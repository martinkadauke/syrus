require "rails_helper"

RSpec.describe BranchDivergenceRecovery do
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
  end

  it "records discarded output and restores the job to implemented" do
    result = described_class.discard!(workflow: workflow, user: user)

    expect(result).to be_success
    expect(workflow.reload.artifact("branch_divergence_recovery")).to include(
      "action" => "discarded",
      "user_id" => user.id
    )
    expect(job.reload).to be_implemented
  end

  it "force-pushes with a lease against the observed remote SHA" do
    Dir.mktmpdir("syrus-branch-divergence-recovery") do |dir|
      git = instance_double(GitRunner)
      client = instance_double(GithubClient, access_token: "token")

      allow(WorkflowWorkspace).to receive(:path_for).with(workflow).and_return(Pathname.new(dir))
      allow(GitRunner).to receive(:new).and_return(git)
      allow(GithubClient).to receive(:for).with(repository: repository, user: user).and_return(client)
      allow(git).to receive(:run)

      result = described_class.force_push!(workflow: workflow, user: user)

      expect(result).to be_success
      expect(git).to have_received(:run).with(
        "push",
        "--force-with-lease=refs/heads/syrus/issue-42-1:remote-sha",
        repository.authenticated_push_url("token"),
        "HEAD:refs/heads/syrus/issue-42-1",
        chdir: dir
      )
      expect(workflow.reload.artifact("branch_divergence_recovery")).to include("action" => "force_pushed")
      expect(job.reload).to be_implemented
    end
  end

  it "does not force-push approved jobs" do
    job.update!(state: "approved")

    result = described_class.force_push!(workflow: workflow, user: user)

    expect(result).not_to be_success
    expect(result.error).to eq("Unapprove before replacing the PR branch.")
  end
end
