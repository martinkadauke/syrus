require "rails_helper"
require "tmpdir"
require "fileutils"

RSpec.describe RunJob do
  # Build a real bare git repo on the local filesystem to play the role of
  # github.com — push lands here, exercising the full clone/branch/commit/push
  # plumbing without leaving the box. Octokit's create_pull_request and
  # fetch_issue are intercepted with WebMock; the agent runner is stubbed so
  # we don't shell out to claude in tests.
  let(:bare_remote_dir) { Pathname.new(Dir.mktmpdir("syrus-bare")) }
  let(:user) { Factories.user(github_token: "ghp_test_token", claude_oauth_token: "oat-test") }
  let(:repository) do
    Factories.repository(
      user: user, owner: "acme", name: "widgets",
      default_branch: "main", trigger_label: "syrus", polling_enabled: true
    )
  end
  let(:job) { Factories.job(repository: repository, issue_number: 42) }

  before do
    seed_remote_with_initial_commit(bare_remote_dir)
    allow_any_instance_of(Repository).to receive(:remote_url).and_return("file://#{bare_remote_dir}")
    allow_any_instance_of(Repository).to receive(:authenticated_push_url).and_return("file://#{bare_remote_dir}")

    stub_request(:get, "https://api.github.com/repos/acme/widgets/issues/42").to_return(
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: { number: 42, title: "Add greeting helper", body: "We need a greeting helper.", state: "open" }.to_json
    )

    @pr_stub = stub_request(:post, "https://api.github.com/repos/acme/widgets/pulls").to_return(
      status: 201,
      headers: { "Content-Type" => "application/json" },
      body: { number: 123, html_url: "https://github.com/acme/widgets/pull/123" }.to_json
    )

    RunJob.agent_runner = ->(workspace_path:, **_) {
      File.write(File.join(workspace_path, "feature.rb"), "def greet = 'hello'\n")
      AgentInvocation::Result.new(turns: 4, exit_status: 0, timed_out: false)
    }
  end

  after do
    RunJob.agent_runner = nil
    FileUtils.rm_rf(bare_remote_dir)
    FileUtils.rm_rf(Rails.root.join("tmp/clones"))
    FileUtils.rm_rf(Rails.root.join("tmp/worktrees"))
  end

  describe "happy path" do
    it "runs the agent, commits its work, pushes the branch, opens the PR, succeeds" do
      described_class.perform_now(job.id)

      job.reload
      expect(job.state).to eq("succeeded")
      expect(job.branch_name).to eq("syrus/issue-42-#{job.id}")
      expect(job.pr_number).to eq(123)
      expect(job.agent_turns).to eq(4)
      expect(job.agent_diff).to include("feature.rb")
      expect(job.agent_diff).to include("def greet")
      expect(@pr_stub).to have_been_requested

      branches = `git --git-dir=#{bare_remote_dir} branch --list 'syrus/*'`.split("\n").map(&:strip)
      expect(branches).to include("syrus/issue-42-#{job.id}")

      files = `git --git-dir=#{bare_remote_dir} ls-tree --name-only syrus/issue-42-#{job.id}`.split("\n")
      expect(files).to include("feature.rb")

      tip = `git --git-dir=#{bare_remote_dir} log -1 --format='%s' syrus/issue-42-#{job.id}`.strip
      expect(tip).to match(/Syrus agent for acme\/widgets#42/)
    end

    it "tears down the worktree" do
      described_class.perform_now(job.id)
      expect(Rails.root.join("tmp/worktrees/#{job.id}")).not_to exist
    end
  end

  describe "pre-pickup cancellation" do
    it "returns early when the Job was cancelled before pickup" do
      job.cancel!
      expect { described_class.perform_now(job.id) }.not_to raise_error
      expect(job.reload.state).to eq("cancelled")
      expect(@pr_stub).not_to have_been_requested
    end
  end

  describe "agent produced no changes" do
    it "marks the Job failed and skips push/PR" do
      RunJob.agent_runner = ->(**_) {
        AgentInvocation::Result.new(turns: 1, exit_status: 0, timed_out: false)
      }

      expect { described_class.perform_now(job.id) }.to raise_error(RunJob::AgentRunFailed, /no changes/)

      job.reload
      expect(job.state).to eq("failed")
      expect(job.agent_turns).to eq(1)
      expect(job.agent_diff).to be_nil
      expect(@pr_stub).not_to have_been_requested
    end
  end

  describe "agent timed out" do
    it "marks the Job failed and skips push/PR" do
      RunJob.agent_runner = ->(**_) {
        AgentInvocation::Result.new(turns: 30, exit_status: nil, timed_out: true)
      }

      expect { described_class.perform_now(job.id) }.to raise_error(RunJob::AgentRunFailed, /timed out/)

      job.reload
      expect(job.state).to eq("failed")
      expect(job.agent_turns).to eq(30)
      expect(@pr_stub).not_to have_been_requested
    end
  end

  describe "PR-opening failure" do
    it "marks the Job failed and cleans up" do
      stub_request(:post, "https://api.github.com/repos/acme/widgets/pulls")
        .to_return(status: 422, body: { message: "Validation Failed" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      expect { described_class.perform_now(job.id) }.to raise_error(Octokit::UnprocessableEntity)

      job.reload
      expect(job.state).to eq("failed")
      expect(Rails.root.join("tmp/worktrees/#{job.id}")).not_to exist
    end
  end

  def seed_remote_with_initial_commit(bare_path)
    Dir.mktmpdir("syrus-seed") do |seed|
      sh("git init -q -b main #{seed}")
      sh("git -C #{seed} commit --allow-empty -q -m 'initial' --author='Seed <seed@example.com>'")
      FileUtils.mkdir_p(bare_path.dirname)
      sh("git clone -q --bare #{seed} #{bare_path}")
    end
  end

  def sh(cmd)
    out, err, status = Open3.capture3({ "GIT_AUTHOR_NAME" => "Seed", "GIT_AUTHOR_EMAIL" => "seed@example.com",
                                        "GIT_COMMITTER_NAME" => "Seed", "GIT_COMMITTER_EMAIL" => "seed@example.com" }, cmd)
    raise "shell failed: #{cmd}\n#{out}\n#{err}" unless status.success?
    out
  end
end
