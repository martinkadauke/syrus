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
  let(:run) { job.initial_run }

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
      AgentInvocation::Result.new(turns: 4, exit_status: 0, timed_out: false, is_error: false, outcome: "success")
    }
  end

  after do
    RunJob.agent_runner = nil
    FileUtils.rm_rf(bare_remote_dir)
    FileUtils.rm_rf(Rails.root.join("tmp/clones"))
    FileUtils.rm_rf(Rails.root.join("tmp/worktrees"))
  end

  describe "happy path (initial run)" do
    it "runs the agent, commits, pushes, opens PR, succeeds — Run holds the metadata, Job holds the thread" do
      described_class.perform_now(run.id)

      run.reload
      job.reload

      expect(run.state).to eq("succeeded")
      expect(run.agent_turns).to eq(4)
      expect(run.agent_outcome).to eq("success")
      expect(run.agent_diff).to include("feature.rb").and include("def greet")
      expect(run.head_sha).to be_present
      expect(run.prompt).to include("Add greeting helper")

      expect(job.state).to eq("open")     # thread stays open even after a successful run
      expect(job.branch_name).to eq("syrus/issue-42-#{job.id}")
      expect(job.pr_number).to eq(123)
      expect(@pr_stub).to have_been_requested

      branches = `git --git-dir=#{bare_remote_dir} branch --list 'syrus/*'`.split("\n").map(&:strip)
      expect(branches).to include(job.branch_name)

      files = `git --git-dir=#{bare_remote_dir} ls-tree --name-only #{job.branch_name}`.split("\n")
      expect(files).to include("feature.rb")

      tip = `git --git-dir=#{bare_remote_dir} log -1 --format='%s' #{job.branch_name}`.strip
      expect(tip).to match(/Syrus agent for acme\/widgets#42/)
    end

    it "tears down the worktree" do
      described_class.perform_now(run.id)
      expect(Rails.root.join("tmp/worktrees/#{run.id}")).not_to exist
    end
  end

  describe "follow-up run" do
    it "pushes a new commit to the existing branch and does NOT open a second PR" do
      # Run the initial run end-to-end first.
      described_class.perform_now(run.id)
      job.reload
      expect(job.pr_number).to eq(123)
      WebMock.reset_executed_requests!

      # Now create a follow-up run.
      followup = Run.create!(job: job, trigger_kind: "pr_comment")
      RunJob.agent_runner = ->(workspace_path:, **_) {
        File.write(File.join(workspace_path, "feature.rb"), "def greet = 'hi there'\n")
        AgentInvocation::Result.new(turns: 2, exit_status: 0, timed_out: false, is_error: false, outcome: "success")
      }
      described_class.perform_now(followup.id)

      followup.reload
      job.reload
      expect(followup.state).to eq("succeeded")
      expect(followup.trigger_kind).to eq("pr_comment")
      expect(job.pr_number).to eq(123)  # unchanged — no new PR
      expect(@pr_stub).not_to have_been_requested  # no new POST /pulls

      # The branch should now have two syrus commits.
      log = `git --git-dir=#{bare_remote_dir} log --format='%s' #{job.branch_name}`.split("\n")
      expect(log.grep(/Syrus/).count).to eq(2)
    end

    it "opens the PR on a replay Run when the initial Run never reached push" do
      # Reproduces Job 10: an initial Run failed mid-agent (no commit,
      # no push, no PR), then a replay Run takes over, succeeds, and
      # MUST open the PR — otherwise the branch makes it to origin
      # with no PR pointing at it.
      job.update!(branch_name: "syrus/issue-42-#{job.id}")  # initial set this before dying
      replay = Run.create!(job: job, trigger_kind: "replay")

      expect {
        described_class.perform_now(replay.id)
      }.to change { job.reload.pr_number }.from(nil).to(123)
      expect(@pr_stub).to have_been_requested
      expect(replay.reload.state).to eq("succeeded")
    end

    it "does not open a second PR on a replay after the initial already opened one" do
      described_class.perform_now(run.id)
      expect(job.reload.pr_number).to eq(123)
      WebMock.reset_executed_requests!

      replay = Run.create!(job: job, trigger_kind: "replay")
      RunJob.agent_runner = ->(workspace_path:, **_) {
        File.write(File.join(workspace_path, "feature.rb"), "def greet = 'hi again'\n")
        AgentInvocation::Result.new(turns: 2, exit_status: 0, timed_out: false, is_error: false, outcome: "success")
      }
      described_class.perform_now(replay.id)

      expect(@pr_stub).not_to have_been_requested
      expect(job.reload.pr_number).to eq(123)  # unchanged
    end

    it "captures only the branch's contribution in agent_diff, even when main moves forward" do
      # Initial run lays down feature.rb on the syrus branch.
      described_class.perform_now(run.id)
      job.reload

      # Now main moves forward with an unrelated commit. This is the
      # real-world setup that broke before: PR sat open while we
      # landed other things on main.
      Dir.mktmpdir("syrus-main-bump") do |bump|
        sh("git clone -q #{bare_remote_dir} #{bump}")
        File.write("#{bump}/UNRELATED.md", "this landed on main after the syrus PR was opened\n")
        sh("git -C #{bump} add UNRELATED.md")
        sh("git -C #{bump} commit -q -m 'unrelated main commit'")
        sh("git -C #{bump} push origin main")
      end

      # Spawn a follow-up Run that touches feature.rb.
      followup = Run.create!(job: job, trigger_kind: "pr_comment")
      RunJob.agent_runner = ->(workspace_path:, **_) {
        File.write(File.join(workspace_path, "feature.rb"), "def greet = 'hi there'\n")
        AgentInvocation::Result.new(turns: 2, exit_status: 0, timed_out: false, is_error: false, outcome: "success")
      }
      described_class.perform_now(followup.id)

      followup.reload
      expect(followup.state).to eq("succeeded")
      # The captured diff must NOT include UNRELATED.md as a removal —
      # that file is only on main, never on the syrus branch.
      expect(followup.agent_diff).not_to include("UNRELATED.md")
      expect(followup.agent_diff).to include("feature.rb")
    end
  end

  describe "pre-pickup cancellation" do
    it "returns early when the Run was cancelled before pickup" do
      run.cancel!
      run.save!
      expect { described_class.perform_now(run.id) }.not_to raise_error
      expect(run.reload.state).to eq("cancelled")
      expect(@pr_stub).not_to have_been_requested
    end

    it "returns early when the Job was closed before pickup" do
      job.close_with_reason!("manual")
      expect { described_class.perform_now(run.id) }.not_to raise_error
      expect(@pr_stub).not_to have_been_requested
    end
  end

  describe "agent produced no changes" do
    it "marks the Run failed; Job stays open (replay possible)" do
      RunJob.agent_runner = ->(**_) {
        AgentInvocation::Result.new(turns: 1, exit_status: 0, timed_out: false, is_error: false, outcome: "success")
      }

      expect { described_class.perform_now(run.id) }.to raise_error(RunJob::AgentRunFailed, /no changes/)

      run.reload
      job.reload
      expect(run.state).to eq("failed")
      expect(run.agent_turns).to eq(1)
      expect(run.agent_diff).to be_nil
      expect(job.state).to eq("open")
      expect(@pr_stub).not_to have_been_requested
    end
  end

  describe "agent reported semantic error" do
    it "persists outcome on Run, marks Run failed, Job stays open" do
      RunJob.agent_runner = ->(workspace_path:, **_) {
        File.write(File.join(workspace_path, "partial.rb"), "# half-done")
        AgentInvocation::Result.new(turns: 50, exit_status: 0, timed_out: false,
                                    is_error: true, outcome: "error_max_turns")
      }

      expect { described_class.perform_now(run.id) }.to raise_error(RunJob::AgentRunFailed, /error_max_turns/)

      run.reload
      expect(run.state).to eq("failed")
      expect(run.agent_turns).to eq(50)
      expect(run.agent_outcome).to eq("error_max_turns")
      expect(@pr_stub).not_to have_been_requested
    end
  end

  describe "PR-opening failure" do
    it "marks the Run failed and cleans up the worktree" do
      stub_request(:post, "https://api.github.com/repos/acme/widgets/pulls")
        .to_return(status: 422, body: { message: "Validation Failed" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      expect { described_class.perform_now(run.id) }.to raise_error(Octokit::UnprocessableEntity)

      run.reload
      expect(run.state).to eq("failed")
      expect(Rails.root.join("tmp/worktrees/#{run.id}")).not_to exist
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
