require "rails_helper"
require "ostruct"

RSpec.describe "Steps::MergeTrain*" do
  let(:user) { Factories.user(github_token: "ghp_test") }
  let(:repository) { Factories.repository(user: user, owner: "acme", name: "widgets", auto_merge_enabled: true) }
  let(:epic) { Factories.epic(user: user, repository: repository) }

  def member_job(issue_number:, state: "landing")
    Factories.job_record(
      user: user, repository: repository, epic: epic,
      issue_number: issue_number, state: state,
      pr_number: 500 + issue_number, branch_name: "syrus/issue-#{issue_number}"
    )
  end

  def build_train(members)
    train = MergeTrain.create!(epic: epic, repository: repository, base_branch: "master",
                              integration_branch: "syrus/merge-train-epic-#{epic.id}-x")
    members.each_with_index { |job, i| MergeTrainMember.create!(merge_train: train, job: job, position: i) }
    train
  end

  def step_handler(klass, kind, train, owner_job)
    workflow = Workflow.create!(job: owner_job, trigger_kind: "merge_train", artifacts: { "merge_train_id" => train.id })
    step = Step.create!(workflow: workflow, kind: kind, position: 0)
    run = Run.create!(job: owner_job, step: step, trigger_kind: "merge_train")
    klass.new(run)
  end

  def stub_git(handler, head: "intsha999")
    workspace = instance_double(WorkflowWorkspace, setup: nil, path: Pathname.new("/tmp/ws"), branch_name: "x")
    git = instance_double(GitRunner)
    allow(handler).to receive(:workspace).and_return(workspace)
    allow(handler).to receive(:streaming_git).and_return(git)
    allow(git).to receive(:run)
    allow(git).to receive(:run).with("rev-parse", "HEAD", chdir: "/tmp/ws").and_return("#{head}\n")
    git
  end

  describe Steps::MergeTrainAssemble do
    it "validates members are landing and names the integration branch" do
      a = member_job(issue_number: 1)
      b = member_job(issue_number: 2)
      train = MergeTrain.create!(epic: epic, repository: repository, base_branch: "master")
      [ a, b ].each_with_index { |j, i| MergeTrainMember.create!(merge_train: train, job: j, position: i) }

      step_handler(described_class, "merge_train_assemble", train, b).call

      expect(train.reload.integration_branch).to eq("syrus/merge-train-epic-#{epic.id}-#{train.id}")
    end

    it "fails when a member is not in :landing" do
      a = member_job(issue_number: 1, state: "approved")
      train = MergeTrain.create!(epic: epic, repository: repository, base_branch: "master")
      MergeTrainMember.create!(merge_train: train, job: a, position: 0)

      expect { step_handler(described_class, "merge_train_assemble", train, a).call }
        .to raise_error(Steps::Base::StepFailed, /not in :landing/)
    end
  end

  describe Steps::MergeTrainBuild do
    it "builds the integration branch by merging members in order and marks the train grading" do
      a = member_job(issue_number: 1)
      b = member_job(issue_number: 2)
      train = build_train([ a, b ])
      handler = step_handler(described_class, "merge_train_build", train, b)
      git = stub_git(handler)

      handler.call

      expect(git).to have_received(:run).with("checkout", "-B", train.integration_branch, "FETCH_HEAD", chdir: "/tmp/ws")
      expect(git).to have_received(:run).with("merge", "--no-ff", "-m", anything, "FETCH_HEAD", chdir: "/tmp/ws").twice
      expect(train.reload.state).to eq("grading")
      expect(train.integration_sha).to eq("intsha999")
    end

    it "lets the agent resolve a conflict, then completes the merge" do
      a = member_job(issue_number: 1)
      train = build_train([ a ])
      handler = step_handler(described_class, "merge_train_build", train, a)
      git = stub_git(handler)
      allow(git).to receive(:run)
        .with("merge", "--no-ff", "-m", anything, "FETCH_HEAD", chdir: "/tmp/ws")
        .and_raise(GitRunner::GitError.new([ "merge" ], 1, "CONFLICT (content)"))
      allow(git).to receive(:run).with("rev-parse", "-q", "--verify", "MERGE_HEAD", chdir: "/tmp/ws").and_return("deadbeef")
      allow(git).to receive(:run).with("ls-files", "-u", chdir: "/tmp/ws").and_return("")
      allow(handler).to receive(:run_agent)

      handler.call

      expect(handler).to have_received(:run_agent)
      expect(git).to have_received(:run).with("add", "-A", chdir: "/tmp/ws")
      expect(git).to have_received(:run).with("commit", "--no-edit", chdir: "/tmp/ws")
      expect(train.reload.state).to eq("grading")
    end

    it "fails (and aborts) when the agent leaves unresolved conflict markers" do
      a = member_job(issue_number: 1)
      train = build_train([ a ])
      handler = step_handler(described_class, "merge_train_build", train, a)
      git = stub_git(handler)
      allow(git).to receive(:run)
        .with("merge", "--no-ff", "-m", anything, "FETCH_HEAD", chdir: "/tmp/ws")
        .and_raise(GitRunner::GitError.new([ "merge" ], 1, "CONFLICT (content)"))
      allow(git).to receive(:run).with("rev-parse", "-q", "--verify", "MERGE_HEAD", chdir: "/tmp/ws").and_return("deadbeef")
      allow(git).to receive(:run).with("ls-files", "-u", chdir: "/tmp/ws").and_return("")
      allow(git).to receive(:run)
        .with("diff", "--cached", "--check", chdir: "/tmp/ws")
        .and_raise(GitRunner::GitError.new([ "diff" ], 2, "leftover <<<<<<< markers"))
      allow(handler).to receive(:run_agent)

      expect { handler.call }.to raise_error(Steps::Base::StepFailed, /unresolved conflict markers/)
      expect(git).to have_received(:run).with("merge", "--abort", chdir: "/tmp/ws")
      expect(train.reload.state).not_to eq("grading")
    end
  end

  describe Steps::MergeTrainLand do
    let(:client) { instance_double(GithubClient, access_token: "token") }

    before do
      allow(GithubClient).to receive(:for).and_return(client)
      allow(repository).to receive(:authenticated_push_url).and_return("https://push.example/repo.git")
      allow(client).to receive(:create_pull_request).and_return(OpenStruct.new(number: 777))
      allow(client).to receive(:merge_pull_request).and_return(OpenStruct.new(merged: true))
      allow(client).to receive(:add_issue_comment)
      allow(client).to receive(:close_pull_request)
    end

    it "opens + merges an integration PR atomically, closes member PRs, and marks Jobs merged" do
      a = member_job(issue_number: 1)
      b = member_job(issue_number: 2)
      train = build_train([ a, b ])
      handler = step_handler(described_class, "merge_train_land", train, b)
      allow(handler).to receive(:repository).and_return(repository)
      stub_git(handler)

      handler.call

      expect(client).to have_received(:create_pull_request)
        .with("acme/widgets", hash_including(base: "master", head: train.integration_branch))
      expect(client).to have_received(:merge_pull_request).with("acme/widgets", 777, hash_including(merge_method: "merge"))
      expect(client).to have_received(:close_pull_request).with("acme/widgets", a.pr_number)
      expect(client).to have_received(:close_pull_request).with("acme/widgets", b.pr_number)
      expect(a.reload).to be_closed
      expect(a.closure_reason).to eq("pr_merged")
      expect(b.reload).to be_closed
      expect(train.reload.state).to eq("succeeded")
      expect(train.members.pluck(:state).uniq).to eq([ "merged" ])
    end

    it "fails landing when GitHub does not report the integration PR merged" do
      a = member_job(issue_number: 1)
      train = build_train([ a ])
      handler = step_handler(described_class, "merge_train_land", train, a)
      allow(handler).to receive(:repository).and_return(repository)
      stub_git(handler)
      allow(client).to receive(:merge_pull_request).and_return(OpenStruct.new(merged: false))

      expect { handler.call }.to raise_error(Steps::Base::StepFailed, /did not report/)
      expect(a.reload).not_to be_closed
    end
  end

  describe MergeTrainFailureHandler do
    def train_with_workflow(members, reason:)
      train = build_train(members)
      workflow = Workflow.create!(job: members.last, trigger_kind: "merge_train",
                                  artifacts: { "merge_train_id" => train.id },
                                  failure_reason: reason)
      [ train, workflow ]
    end

    it "fail_lands members (requires re-approval) on a genuine failure" do
      a = member_job(issue_number: 1)
      b = member_job(issue_number: 2)
      train, workflow = train_with_workflow([ a, b ], reason: "loop_exhausted_after_grader_failure")

      described_class.call(workflow: workflow)

      expect(a.reload.state).to eq("implemented")
      expect(b.reload.state).to eq("implemented")
      expect(train.reload.state).to eq("failed")
      expect(train.members.pluck(:state).uniq).to eq([ "failed" ])
    end

    it "defer_lands members (auto-retry) on a transient infrastructure blocker" do
      a = member_job(issue_number: 1)
      train, workflow = train_with_workflow([ a ], reason: "No space left on device")

      described_class.call(workflow: workflow)

      expect(a.reload.state).to eq("approved")
      expect(train.reload.state).to eq("failed")
    end
  end
end
