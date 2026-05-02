require "fileutils"

class JobWorkspace
  attr_reader :path, :branch_name

  # Where the bare clones + worktrees live on disk. Default `~/.syrus`
  # so the agent's chdir is *outside* the operator's main Rails.root —
  # the agent can't accidentally land in app/ or the live tmp/ via a
  # stray relative path. Overridable via SYRUS_DATA_ROOT for specs and
  # for ops who want it on a different volume.
  def self.data_root
    Pathname.new(ENV["SYRUS_DATA_ROOT"] || File.expand_path("~/.syrus"))
  end

  def initialize(run, git: nil)
    @run = run
    @job = run.job
    @repository = @job.repository
    @git = git || GitRunner.new
    @path = self.class.data_root.join("worktrees", @run.id.to_s)
    # Same name across initial + every follow-up Run for this Job —
    # derived from the Job's id, so it's stable as long as the Job
    # is. Use the persisted Job.branch_name when set so the agent's
    # commits land on whatever the initial Run put on origin (or, if
    # the initial died before push, on a freshly-recreated branch).
    @branch_name = @job.branch_name.presence || initial_branch_name
    @env = { "GIT_TERMINAL_PROMPT" => "0" }   # fail fast instead of hanging on a credential prompt
  end

  # Per-Run worktree at <data_root>/worktrees/{run_id}, all rooted in a
  # shared bare clone at <data_root>/clones/{repo_id}.git. setup checks
  # origin for the branch: if it's there we check it out (follow-up
  # case); if it isn't we create it from default (initial case OR
  # recovery from a dead initial Run that never reached the push step).
  def setup
    ensure_bare_clone
    fetch_origin
    FileUtils.mkdir_p(path.dirname)

    if branch_exists?(@branch_name)
      add_worktree_on_existing_branch
    else
      add_worktree_on_new_branch
    end
  end

  def cleanup
    return unless path.exist?
    @git.run("worktree", "remove", "--force", path.to_s, chdir: bare_clone_path.to_s)
  rescue GitRunner::GitError
    FileUtils.rm_rf(path)
    @git.run("worktree", "prune", chdir: bare_clone_path.to_s) if bare_clone_path.exist?
  end

  def bare_clone_path
    self.class.data_root.join("clones", "#{@repository.id}.git")
  end

  private

  def initial_branch_name
    "syrus/issue-#{@job.issue_number}-#{@job.id}"
  end

  # Use the authenticated URL (token in the URL) for both clone and
  # fetch — private repos need it. After clone, scrub the persisted
  # `origin` URL back to anonymous so the token isn't sitting in
  # .git/config indefinitely. Each subsequent fetch passes the
  # authenticated URL transiently in argv (same pattern push uses).
  def ensure_bare_clone
    return if bare_clone_path.exist?
    FileUtils.mkdir_p(bare_clone_path.dirname)
    @git.run("clone", "--bare", authenticated_url, bare_clone_path.to_s, env: @env)
    @git.run("remote", "set-url", "origin", @repository.remote_url, chdir: bare_clone_path.to_s)
  end

  # Pass the authenticated URL explicitly (instead of just `origin`),
  # plus an explicit refspec since we're not using the named remote.
  # Mirrors every remote head into local refs/heads/* — covers
  # default-branch updates AND any syrus / external branches we'll
  # need to check out later.
  def fetch_origin
    @git.run("fetch", authenticated_url, "+refs/heads/*:refs/heads/*", chdir: bare_clone_path.to_s, env: @env)
  end

  def authenticated_url
    @repository.authenticated_push_url(@job.user.github_token)
  end

  # `git branch --list <name>` returns 0 with empty output when the
  # branch doesn't exist, vs 0 with the branch name when it does —
  # so no exception path here, just a presence check on stdout.
  def branch_exists?(name)
    output = @git.run("branch", "--list", name, chdir: bare_clone_path.to_s)
    output.strip.present?
  end

  def add_worktree_on_new_branch
    @git.run(
      "worktree", "add", path.to_s, "-b", @branch_name, @repository.default_branch,
      chdir: bare_clone_path.to_s
    )
  end

  def add_worktree_on_existing_branch
    @git.run(
      "worktree", "add", path.to_s, @branch_name,
      chdir: bare_clone_path.to_s
    )
  end
end
