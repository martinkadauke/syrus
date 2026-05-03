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
    # Tests use a local file:// bare repo which doesn't need auth.
    # Production stubs token into URL — for the test, just stub the
    # auth-URL helper to return the same file:// path so clone+fetch
    # against the local bare repo works whichever URL the code picks.
    allow_any_instance_of(Repository).to receive(:authenticated_push_url).and_return("file://#{bare_remote_dir}")
    @syrus_data_root = Dir.mktmpdir("syrus-test-data")
    ENV["SYRUS_DATA_ROOT"] = @syrus_data_root
  end

  after do
    ENV.delete("SYRUS_DATA_ROOT")
    FileUtils.rm_rf(bare_remote_dir)
    FileUtils.rm_rf(@syrus_data_root) if @syrus_data_root
  end

  describe "initial run" do
    it "lazy-clones the bare cache once and reuses it on subsequent setups" do
      workspace = described_class.new(job.initial_run)
      workspace.setup
      expect(workspace.bare_clone_path).to exist

      # Drop a sentinel inside the bare clone. If the second setup
      # re-clones (which would obliterate the directory), the sentinel
      # disappears. If it reuses the existing clone, the sentinel
      # survives.
      sentinel = workspace.bare_clone_path.join("SYRUS-CACHE-SENTINEL")
      File.write(sentinel, "set after first clone")
      workspace.cleanup

      second_job = Factories.job(repository: repository, issue_number: 8)
      workspace2 = described_class.new(second_job.initial_run)
      workspace2.setup

      expect(sentinel).to exist
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

    it "prunes local refs/heads/* whose remote counterpart was deleted (e.g. GitHub auto-deleted after merge)" do
      # First setup: clones + fetches main only.
      first = described_class.new(job.initial_run)
      first.setup
      bare = first.bare_clone_path

      # Pretend the remote grew a stale branch, then deleted it.
      sh("git --git-dir=#{bare_remote_dir} branch ephemeral main")
      Factories.job(repository: repository, issue_number: 100).initial_run.tap do |r|
        described_class.new(r).setup.tap { described_class.new(r).cleanup }
      end
      expect(`git --git-dir=#{bare} branch --list ephemeral`.strip).to be_present  # we picked it up

      sh("git --git-dir=#{bare_remote_dir} branch -D ephemeral")
      expect(`git --git-dir=#{bare_remote_dir} branch --list ephemeral`.strip).to be_blank

      # Next setup should --prune the now-missing branch from our local bare.
      Factories.job(repository: repository, issue_number: 101).initial_run.tap do |r|
        described_class.new(r).setup.tap { described_class.new(r).cleanup }
      end
      expect(`git --git-dir=#{bare} branch --list ephemeral`.strip).to be_blank

      first.cleanup
    end

    it "force-clears its own worktree before fetch (handles Solid Queue retry of the same RunJob)" do
      # Simulate the killed-mid-flight scenario: the first perform set
      # up a worktree on the branch, then died. The Run is still
      # state=running because @run.fail! never fired. Solid Queue
      # re-claims and a NEW perform invocation is created on the same
      # Run id. setup must clear its own previous worktree even though
      # the Run state isn't terminal.
      run = job.initial_run
      first_attempt = described_class.new(run)
      first_attempt.setup
      # Run state is "running" via @run.start! in real flow. Mirror that here.
      run.update!(state: "running", started_at: Time.current)
      orphan_path = first_attempt.path
      expect(orphan_path).to exist  # left behind by killed worker

      # Second attempt = new JobWorkspace on the same Run. setup must
      # not blow up at fetch with "refusing to fetch into branch ...".
      retry_attempt = described_class.new(run)
      expect { retry_attempt.setup }.not_to raise_error
      expect(retry_attempt.path).to exist
      retry_attempt.cleanup
    end

    it "sweeps orphan worktrees from prior crashed Runs (terminal Run, worktree still registered)" do
      # First Run sets up a worktree, then "crashes" mid-flight: we
      # mark its Run failed and DON'T call cleanup, simulating a
      # SIGKILLed RunJob that never reached its `ensure` block.
      first_run = job.initial_run
      first_workspace = described_class.new(first_run)
      first_workspace.setup
      first_run.update!(state: "failed", finished_at: Time.current)
      orphan_path = first_workspace.path
      expect(orphan_path).to exist  # still on disk

      # A new Run on a *different* Job for the same repo would normally
      # fail at fetch with "refusing to fetch into branch X checked out
      # at <orphan>". The sweep on setup must drop the orphan before
      # fetch_origin runs.
      second_job = Factories.job(repository: repository, issue_number: 99)
      second_workspace = described_class.new(second_job.initial_run)
      expect { second_workspace.setup }.not_to raise_error
      expect(second_workspace.path).to exist

      # Orphan is gone — both the directory on disk and the git
      # worktree registration. realpath normalizes /var vs /private/var
      # on macOS so the comparison works either way.
      expect(orphan_path).not_to exist
      list = `git --git-dir=#{first_workspace.bare_clone_path} worktree list --porcelain`
      registered = list.scan(/^worktree (.+)$/).flatten.select { |p| File.exist?(p) }.map { |p| File.realpath(p) }
      expect(registered).not_to include(File.realpath(second_workspace.path.parent) + "/#{File.basename(orphan_path)}")
      second_workspace.cleanup
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

    it "recovers when Job.branch_name is set but the branch never made it to origin (dead initial run)" do
      # Reproduces the "killed bin/dev mid-initial-run, then hit Run again"
      # scenario: Job.branch_name was persisted right after JobWorkspace.setup
      # in the dead Run, but origin never received the push.
      job.update!(branch_name: "syrus/issue-7-#{job.id}")
      followup = Run.create!(job: job, trigger_kind: "replay")

      followup_workspace = described_class.new(followup)
      followup_workspace.setup
      expect(followup_workspace.path).to exist
      head_branch = `git -C #{followup_workspace.path} rev-parse --abbrev-ref HEAD`.strip
      expect(head_branch).to eq("syrus/issue-7-#{job.id}")  # branch is created fresh from default
      followup_workspace.cleanup
    end

    it "force-clears a zombie Run's worktree that's still using this Job's branch (PR-merged-and-deleted-on-origin scenario)" do
      # Initial Run sets up a worktree on syrus/issue-7-N, then dies
      # mid-execution: Run state stuck at "running", worktree still on
      # disk, branch still registered to that worktree. Meanwhile the
      # PR was merged on GitHub and the branch deleted. Our fetch with
      # --prune in the next Run would (in the wild) delete the local
      # ref but leave the worktree registration pointing at it; the
      # subsequent `worktree add` fails with "already checked out".
      # The new force_clear_worktrees_on_my_branch step prevents this
      # by removing the zombie worktree before we touch fetch.
      initial = job.initial_run
      ws1 = described_class.new(initial)
      ws1.setup

      # Don't cleanup — simulate the zombie state. Mark the Run as
      # still "running" (which is what an in-flight Run looks like).
      initial.update_columns(state: "running", started_at: 1.minute.ago, last_heartbeat_at: 1.minute.ago)

      job.update!(branch_name: "syrus/issue-7-#{job.id}")
      replay = Run.create!(job: job, trigger_kind: "replay")

      ws2 = described_class.new(replay)
      expect { ws2.setup }.not_to raise_error
      expect(ws2.path).to exist
      head_branch = `git -C #{ws2.path} rev-parse --abbrev-ref HEAD`.strip
      expect(head_branch).to eq("syrus/issue-7-#{job.id}")

      # The zombie worktree is gone.
      expect(ws1.path).not_to exist
      ws2.cleanup
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
