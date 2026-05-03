require "fileutils"

class JobWorkspace
  # Shallow clone depth — keeps disk and bandwidth usage modest while
  # giving enough history for three-dot diffs (`git diff main...HEAD`)
  # even when main has advanced since the branch was created.
  CLONE_DEPTH = 50

  attr_reader :path, :branch_name

  # Where per-Run clones live on disk. Default `~/.syrus` so the
  # agent's chdir is *outside* the operator's main Rails.root.
  # Overridable via SYRUS_DATA_ROOT for specs and for ops who want
  # it on a different volume.
  def self.data_root
    Pathname.new(ENV["SYRUS_DATA_ROOT"] || File.expand_path("~/.syrus"))
  end

  def initialize(run, git: nil)
    @run = run
    @job = run.job
    @repository = @job.repository
    @git = git || GitRunner.new
    @path = self.class.data_root.join("runs", @run.id.to_s)
    # Same name across initial + every follow-up Run for this Job —
    # derived from the Job's id, so it's stable as long as the Job
    # is. Use the persisted Job.branch_name when set so the agent's
    # commits land on whatever the initial Run put on origin (or, if
    # the initial died before push, on a freshly-recreated branch).
    @branch_name = @job.branch_name.presence || initial_branch_name
    @env = { "GIT_TERMINAL_PROMPT" => "0" }  # fail fast instead of hanging on a credential prompt
  end

  # Fresh per-Run clone at <data_root>/runs/<run_id>/. No shared
  # state with other concurrent Runs — eliminates the bare-clone
  # races that could orphan a worktree's git history.
  #
  # Always clones the default branch so it is a local ref available
  # for three-dot diff (`git diff main...HEAD`). If the target branch
  # already exists on origin (follow-up Run), fetches it and checks
  # it out; otherwise creates a new branch from the default-branch
  # tip (initial Run, or recovery from a dead initial Run that never
  # reached push).
  def setup
    FileUtils.mkdir_p(path.dirname)

    @git.run(
      "clone", "--depth", CLONE_DEPTH.to_s,
      "--branch", @repository.default_branch,
      "--no-tags", authenticated_url, path.to_s,
      env: @env
    )

    # Check for our target branch on origin before scrubbing the
    # token from .git/config — ls-remote needs the authenticated URL.
    remote_ref = @git.run(
      "ls-remote", "--heads", authenticated_url,
      "refs/heads/#{@branch_name}",
      chdir: path.to_s, env: @env
    )

    # Scrub the token from the persisted origin URL now that the
    # clone is done. Each subsequent fetch/push passes it transiently
    # in argv (same pattern as before).
    @git.run("remote", "set-url", "origin", @repository.remote_url, chdir: path.to_s)

    if remote_ref.strip.present?
      fetch_and_checkout_existing_branch
    else
      create_new_branch
    end
  end

  def cleanup
    FileUtils.rm_rf(path)
  end

  private

  def initial_branch_name
    if @job.cron?
      "syrus/scheduled-#{@job.scheduled_task_id}-#{@job.id}"
    else
      "syrus/issue-#{@job.issue_number}-#{@job.id}"
    end
  end

  # Use the authenticated URL (token in the URL) for clone and
  # fetch — private repos need it. Scrubbed from origin after clone
  # so the token isn't sitting in .git/config; passed transiently
  # in argv on subsequent operations.
  def authenticated_url
    @repository.authenticated_push_url(@job.user.github_token)
  end

  def fetch_and_checkout_existing_branch
    @git.run(
      "fetch", "--depth", CLONE_DEPTH.to_s, authenticated_url,
      "refs/heads/#{@branch_name}:refs/heads/#{@branch_name}",
      chdir: path.to_s, env: @env
    )
    @git.run("checkout", @branch_name, chdir: path.to_s)
  end

  def create_new_branch
    @git.run("checkout", "-b", @branch_name, chdir: path.to_s)
  end
end
