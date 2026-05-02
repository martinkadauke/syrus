require "fileutils"

class JobWorkspace
  attr_reader :path, :branch_name

  def initialize(run, git: nil)
    @run = run
    @job = run.job
    @repository = @job.repository
    @git = git || GitRunner.new
    @path = Rails.root.join("tmp/worktrees/#{@run.id}")
    @branch_name = @run.initial? ? initial_branch_name : @job.branch_name
  end

  # Per-Run worktree: bare clone at tmp/clones/{repo_id}.git, worktree at
  # tmp/worktrees/{run_id}. Initial runs create a new syrus branch off
  # the repo's default branch. Follow-up runs (pr_comment / ci_failure /
  # replay) check out the existing branch the initial run pushed.
  def setup
    raise ArgumentError, "follow-up run with no branch_name on Job" if @branch_name.blank?
    ensure_bare_clone
    fetch_origin
    if @run.initial?
      add_worktree_on_new_branch
    else
      add_worktree_on_existing_branch
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
    Rails.root.join("tmp/clones/#{@repository.id}.git")
  end

  private

  def initial_branch_name
    "syrus/issue-#{@job.issue_number}-#{@job.id}"
  end

  def ensure_bare_clone
    return if bare_clone_path.exist?
    FileUtils.mkdir_p(bare_clone_path.dirname)
    @git.run("clone", "--bare", @repository.remote_url, bare_clone_path.to_s)
  end

  # `git fetch origin` (no refspec) on a bare clone pulls every remote
  # head into local refs/heads/*. That covers both default-branch updates
  # and any syrus branches a prior run pushed.
  def fetch_origin
    @git.run("fetch", "origin", chdir: bare_clone_path.to_s)
  end

  def add_worktree_on_new_branch
    FileUtils.mkdir_p(path.dirname)
    @git.run(
      "worktree", "add", path.to_s, "-b", @branch_name, @repository.default_branch,
      chdir: bare_clone_path.to_s
    )
  end

  def add_worktree_on_existing_branch
    FileUtils.mkdir_p(path.dirname)
    @git.run(
      "worktree", "add", path.to_s, @branch_name,
      chdir: bare_clone_path.to_s
    )
  end
end
