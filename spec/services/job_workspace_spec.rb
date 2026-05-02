require "rails_helper"
require "tmpdir"

RSpec.describe JobWorkspace do
  let(:bare_remote_dir) { Pathname.new(Dir.mktmpdir("syrus-jw-bare")) }
  let(:user) { Factories.user(github_token: "ghp_test_token") }
  let(:repository) do
    Factories.repository(user: user, owner: "acme", name: "widgets", default_branch: "main")
  end
  let(:job) { Factories.job(repository: repository, issue_number: 7) }

  before do
    seed_remote(bare_remote_dir)
    allow_any_instance_of(Repository).to receive(:remote_url).and_return("file://#{bare_remote_dir}")
  end

  after do
    FileUtils.rm_rf(bare_remote_dir)
    FileUtils.rm_rf(Rails.root.join("tmp/clones"))
    FileUtils.rm_rf(Rails.root.join("tmp/worktrees"))
  end

  describe "initial run" do
    it "lazy-clones the bare cache once and reuses it on subsequent setups" do
      workspace = described_class.new(job.initial_run)
      workspace.setup
      expect(workspace.bare_clone_path).to exist
      workspace.cleanup

      second_job = Factories.job(repository: repository, issue_number: 8)
      workspace2 = described_class.new(second_job.initial_run)
      expect_any_instance_of(GitRunner).not_to receive(:run).with("clone", anything, anything, anything)
      workspace2.setup
      workspace2.cleanup
    end

    it "creates a fresh worktree on a new branch derived from job.id" do
      workspace = described_class.new(job.initial_run)
      workspace.setup
      expect(workspace.path).to exist
      head_branch = `git -C #{workspace.path} rev-parse --abbrev-ref HEAD`.strip
      expect(head_branch).to eq("syrus/issue-7-#{job.id}")
    end

    it "removes the worktree on cleanup" do
      workspace = described_class.new(job.initial_run)
      workspace.setup
      workspace.cleanup
      expect(workspace.path).not_to exist
    end

    it "is idempotent on cleanup with no worktree present" do
      workspace = described_class.new(job.initial_run)
      expect { workspace.cleanup }.not_to raise_error
    end
  end

  describe "follow-up run" do
    it "checks out the existing branch instead of creating a new one" do
      # First, run an initial workspace + push a commit so the branch
      # exists on origin.
      initial_workspace = described_class.new(job.initial_run)
      initial_workspace.setup
      sh("git -C #{initial_workspace.path} commit --allow-empty -q -m 'initial work'")
      sh("git -C #{initial_workspace.path} push origin #{initial_workspace.branch_name}")
      initial_workspace.cleanup

      # Now simulate a follow-up: branch_name is already known on the Job.
      job.update!(branch_name: initial_workspace.branch_name)
      followup = Run.create!(job: job, trigger_kind: "pr_comment")

      followup_workspace = described_class.new(followup)
      followup_workspace.setup
      expect(followup_workspace.path).to exist
      head_branch = `git -C #{followup_workspace.path} rev-parse --abbrev-ref HEAD`.strip
      expect(head_branch).to eq(initial_workspace.branch_name)
      followup_workspace.cleanup
    end

    it "raises when the parent Job has no branch_name yet" do
      followup = Run.create!(job: job, trigger_kind: "pr_comment")
      expect { described_class.new(followup).setup }.to raise_error(ArgumentError, /no branch_name/)
    end
  end

  def seed_remote(bare_path)
    Dir.mktmpdir("syrus-seed") do |seed|
      sh("git init -q -b main #{seed}")
      sh("git -C #{seed} commit --allow-empty -q -m 'initial'")
      FileUtils.mkdir_p(bare_path.dirname)
      sh("git clone -q --bare #{seed} #{bare_path}")
    end
  end

  def sh(cmd)
    out, err, status = Open3.capture3(
      { "GIT_AUTHOR_NAME" => "Seed", "GIT_AUTHOR_EMAIL" => "seed@example.com",
        "GIT_COMMITTER_NAME" => "Seed", "GIT_COMMITTER_EMAIL" => "seed@example.com" },
      cmd
    )
    raise "shell failed: #{cmd}\n#{out}\n#{err}" unless status.success?
    out
  end
end
