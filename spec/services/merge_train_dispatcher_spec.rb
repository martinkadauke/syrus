require "rails_helper"

RSpec.describe MergeTrainDispatcher do
  let(:user) { Factories.user(github_token: "ghp_test") }
  let(:repository) { Factories.repository(user: user, auto_merge_enabled: true) }
  let(:epic) { Factories.epic(user: user, repository: repository) }

  def approved_child(issue_number)
    Factories.job_record(
      user: user, repository: repository, epic: epic,
      issue_number: issue_number, state: "approved",
      pr_number: 500 + issue_number, branch_name: "syrus/issue-#{issue_number}"
    )
  end

  before do
    AppSetting.current.update!(merge_train_enabled: true)
    allow(StepDispatcher).to receive(:start_workflow)
  end

  it "creates a train, locks members into :landing, and starts the workflow" do
    a = approved_child(1)
    b = approved_child(2)

    workflow = described_class.try_dispatch!(epic)

    expect(workflow).to be_present
    expect(workflow.trigger_kind).to eq("merge_train")
    train = MergeTrain.last
    expect(train.epic).to eq(epic)
    expect(train.base_branch).to eq(repository.default_branch)
    expect(train.members.count).to eq(2)
    expect(workflow.artifact("merge_train_id")).to eq(train.id)
    expect(a.reload.state).to eq("landing")
    expect(b.reload.state).to eq("landing")
    expect(StepDispatcher).to have_received(:start_workflow).with(workflow)
  end

  it "does nothing when the merge-train flag is off" do
    AppSetting.current.update!(merge_train_enabled: false)
    approved_child(1)

    expect(described_class.try_dispatch!(epic)).to be_nil
    expect(MergeTrain.count).to eq(0)
  end

  it "does nothing when the Epic is not ready (a child is unapproved)" do
    approved_child(1)
    Factories.job_record(user: user, repository: repository, epic: epic, issue_number: 2,
                         state: "implemented", pr_number: 502, branch_name: "syrus/issue-2")

    expect(described_class.try_dispatch!(epic)).to be_nil
    expect(MergeTrain.count).to eq(0)
  end

  it "does nothing when the repository already has a landing in progress" do
    approved_child(1)
    Factories.job_record(user: user, repository: repository, issue_number: 99, state: "landing", pr_number: 999)

    expect(described_class.try_dispatch!(epic)).to be_nil
    expect(MergeTrain.count).to eq(0)
  end
end
