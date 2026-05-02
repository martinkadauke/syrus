require "fileutils"

class JobWorkspace
  attr_reader :path, :branch_name

  def initialize(job, git: nil)
    @job = job
    @repository = job.repository
    @git = git || GitRunner.new
    @path = Rails.root.join("tmp/worktrees/#{@job.id}")
    @branch_name = "syrus/issue-#{@job.issue_number}-#{@job.id}"
  end

  # Ensures the bare clone exists (cloned on first use, fetched on later runs)
  # and adds a fresh worktree on a new branch off origin/{default_branch}.
  def setup
    ensure_bare_clone
    fetch_default_branch
    add_worktree
  end

  def cleanup
    return unless path.exist?
    @git.run("worktree", "remove", "--force", path.to_s, chdir: bare_clone_path.to_s)
  rescue GitRunner::GitError
    # Best-effort: fall back to plain rm if git refuses
    FileUtils.rm_rf(path)
    @git.run("worktree", "prune", chdir: bare_clone_path.to_s) if bare_clone_path.exist?
  end

  def bare_clone_path
    Rails.root.join("tmp/clones/#{@repository.id}.git")
  end

  private

  def ensure_bare_clone
    return if bare_clone_path.exist?
    FileUtils.mkdir_p(bare_clone_path.dirname)
    @git.run("clone", "--bare", @repository.remote_url, bare_clone_path.to_s)
  end

  def fetch_default_branch
    @git.run("fetch", "origin", @repository.default_branch, chdir: bare_clone_path.to_s)
  end

  def add_worktree
    FileUtils.mkdir_p(path.dirname)
    # Bare clones store fetched branches as refs/heads/* directly — there's no
    # refs/remotes/origin/main, so start the new branch from the local ref.
    @git.run(
      "worktree", "add", path.to_s, "-b", branch_name, @repository.default_branch,
      chdir: bare_clone_path.to_s
    )
  end
end
