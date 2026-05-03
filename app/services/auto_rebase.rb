require "fileutils"

# Attempts a non-interactive `git rebase origin/<base>` on the Job's
# branch. If it exits clean, force-push the result and skip the
# agentic rebase Run entirely. If conflicts remain, abort and signal
# the caller to fall back to the agent.
#
# Whatever merge drivers the target repo declares in `.gitattributes`
# get a chance to do their job — Syrus discovers them by convention
# (a `merge=NAME` reference paired with an executable `bin/merge-NAME`
# script in the worktree) and registers them in the bare clone's
# `.git/config` before running rebase. No Ruby/Rails-specific
# knowledge in Syrus; the driver lives in (and is shipped by) the
# target repo.
class AutoRebase
  Result = Data.define(:succeeded, :reason, :note) do
    def succeeded?
      succeeded
    end

    def to_s
      [ reason, note ].compact.reject(&:empty?).join(" — ")
    end
  end

  def initialize(job, git: nil)
    @job = job
    @git = git || GitRunner.new
    @env = { "GIT_TERMINAL_PROMPT" => "0" }
  end

  def call
    return Result.new(false, "no_branch", nil)  if @job.branch_name.blank?
    return Result.new(false, "no_repo", nil)    unless @job.repository
    return Result.new(false, "no_clone", nil)   unless bare_clone_path.exist?

    cleanup_worktree
    create_worktree

    register_merge_drivers
    fetch_base

    pre_sha = head_sha

    if rebase_succeeded?
      post_sha = head_sha
      if pre_sha == post_sha
        Result.new(true, "rebased", "no-op (already up-to-date)")
      else
        force_push
        Result.new(true, "rebased", "advanced #{pre_sha[0, 7]} → #{post_sha[0, 7]}")
      end
    else
      abort_rebase
      Result.new(false, "conflict", nil)
    end
  rescue StandardError => e
    abort_rebase
    Rails.logger.warn("[AutoRebase] job #{@job.id} unexpected error: #{e.class}: #{e.message}")
    Result.new(false, "error", e.message)
  ensure
    cleanup_worktree
  end

  private

  def bare_clone_path
    JobWorkspace.data_root.join("clones", "#{@job.repository.id}.git")
  end

  def worktree_path
    JobWorkspace.data_root.join("worktrees", "auto-rebase-#{@job.id}")
  end

  def authenticated_url
    @job.repository.authenticated_push_url(@job.user.github_token)
  end

  def base_branch
    @job.repository.default_branch
  end

  def create_worktree
    FileUtils.mkdir_p(worktree_path.dirname)
    @git.run("worktree", "add", worktree_path.to_s, @job.branch_name, chdir: bare_clone_path.to_s)
  end

  def cleanup_worktree
    return unless worktree_path.exist?
    @git.run("worktree", "remove", "--force", worktree_path.to_s, chdir: bare_clone_path.to_s) rescue nil
    FileUtils.rm_rf(worktree_path) if worktree_path.exist?
    @git.run("worktree", "prune", chdir: bare_clone_path.to_s) rescue nil
  end

  # Discover and register custom merge drivers the target repo
  # declares. Convention:
  #
  #   .gitattributes:    db/schema.rb merge=ruby_schema
  #   repo file:         bin/merge-ruby_schema  (executable)
  #
  # Each `merge=NAME` reference becomes
  #   git config merge.NAME.driver "<absolute-path-to-script> %O %A %B"
  # in the bare clone, so subsequent worktrees on this clone (this
  # rebase, and the agentic fallback if it runs) benefit.
  #
  # Idempotent. Repos without `.gitattributes` or without matching
  # scripts are silently skipped — Syrus has no opinion on whether
  # a target repo "should" have merge drivers; it just respects
  # what's declared.
  def register_merge_drivers
    attrs = worktree_path.join(".gitattributes")
    return unless attrs.exist?

    names = attrs.each_line.flat_map { |line| line.scan(/merge=(\S+)/).flatten }.uniq
    names.each do |name|
      script = worktree_path.join("bin", "merge-#{name}")
      next unless script.exist? && File.executable?(script)
      @git.run(
        "config", "merge.#{name}.driver",
        "#{script} %O %A %B",
        chdir: bare_clone_path.to_s
      )
    end
  end

  def fetch_base
    @git.run("fetch", authenticated_url,
             "+refs/heads/#{base_branch}:refs/remotes/origin/#{base_branch}",
             chdir: worktree_path.to_s, env: @env)
  end

  def rebase_succeeded?
    @git.run("rebase", "origin/#{base_branch}", chdir: worktree_path.to_s, env: @env)
    true
  rescue GitRunner::GitError
    false
  end

  def abort_rebase
    return unless worktree_path.exist?
    @git.run("rebase", "--abort", chdir: worktree_path.to_s) rescue nil
  end

  def force_push
    @git.run("push", "--force", authenticated_url,
             "HEAD:refs/heads/#{@job.branch_name}",
             chdir: worktree_path.to_s, env: @env)
  end

  def head_sha
    @git.run("rev-parse", "HEAD", chdir: worktree_path.to_s).strip
  end
end
