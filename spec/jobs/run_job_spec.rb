require "rails_helper"
require "tmpdir"
require "fileutils"

RSpec.describe RunJob do
  # Build a real bare git repo on the local filesystem to play the role of
  # github.com — push lands here, exercising the full clone/branch/commit/push
  # plumbing without leaving the box. The Octokit create_pull_request call is
  # intercepted with WebMock so we can assert it would have been made.
  let(:bare_remote_dir) { Pathname.new(Dir.mktmpdir("syrus-bare")) }
  let(:user) { Factories.user(github_token: "ghp_test_token") }
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

    @pr_stub = stub_request(:post, "https://api.github.com/repos/acme/widgets/pulls")
      .to_return(
        status: 201,
        headers: { "Content-Type" => "application/json" },
        body: { number: 123, html_url: "https://github.com/acme/widgets/pull/123" }.to_json
      )
  end

  after do
    FileUtils.rm_rf(bare_remote_dir)
    FileUtils.rm_rf(Rails.root.join("tmp/clones"))
    FileUtils.rm_rf(Rails.root.join("tmp/worktrees"))
  end

  describe "happy path" do
    it "branches from default, commits the marker, pushes, opens the PR, succeeds" do
      described_class.perform_now(job.id)

      job.reload
      expect(job.state).to eq("succeeded")
      expect(job.branch_name).to eq("syrus/issue-42-#{job.id}")
      expect(job.pr_number).to eq(123)
      expect(job.started_at).to be_present
      expect(job.finished_at).to be_present
      expect(@pr_stub).to have_been_requested

      branches = `git --git-dir=#{bare_remote_dir} branch --list 'syrus/*'`.split("\n").map(&:strip)
      expect(branches).to include("syrus/issue-42-#{job.id}")

      tip = `git --git-dir=#{bare_remote_dir} log -1 --format='%s' syrus/issue-42-#{job.id}`.strip
      expect(tip).to match(/Syrus placeholder for acme\/widgets#42/)

      files = `git --git-dir=#{bare_remote_dir} ls-tree --name-only syrus/issue-42-#{job.id}`.split("\n")
      expect(files).to include(".syrus-marker")

      expect(job.job_logs.count).to be > 0
      expect(job.job_logs.maximum(:sequence)).to be >= 0
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
