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
    sweep_orphan_worktrees       # before fetch — orphan worktrees lock branches
    force_clear_own_worktree      # before fetch — handles RunJob retries
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
  #
  # `--prune` drops local refs/heads/* that no longer exist on origin
  # (typically: branches GitHub auto-deleted after PR merge). Without
  # it the bare clone accumulates dead refs forever and `git fetch
  # +refs/heads/*:refs/heads/*` never gets to drop them. Pruning a
  # branch that's currently checked out in a worktree is a no-op —
  # git refuses to delete it — so this is safe even mid-Run.
  def fetch_origin
    @git.run("fetch", "--prune", authenticated_url, "+refs/heads/*:refs/heads/*", chdir: bare_clone_path.to_s, env: @env)
  end

  def authenticated_url
    @repository.authenticated_push_url(@job.user.github_token)
  end

  # When Solid Queue retries a RunJob (worker died mid-perform → claim
  # released → another worker re-claims the same SQ::Job), the previous
  # attempt may have left a worktree at our target path with the branch
  # registered as checked out. The orphan sweep would skip it because
  # Run state is "running" (set by the killed attempt's `@run.start!`,
  # never reset). Force-clear our own path defensively before fetch.
  #
  # Skip the noisy `worktree remove` call when the path doesn't exist —
  # that's the normal first-run case, and git's "fatal: '...' is not a
  # working tree" stderr line gets streamed into the JobLog before we
  # rescue it (GitRunner streams line-by-line). Prune still runs to
  # clean any registrations whose dir is missing.
  def force_clear_own_worktree
    if File.exist?(path)
      @git.run("worktree", "remove", "--force", path.to_s, chdir: bare_clone_path.to_s) rescue nil
      FileUtils.rm_rf(path) if File.exist?(path)
    end
    @git.run("worktree", "prune", chdir: bare_clone_path.to_s) rescue nil
  end

  # Garbage-collect worktree registrations whose Run is terminal (or
  # whose Run record is gone). These come from RunJob processes that
  # got SIGKILLed before their `ensure` block could run — typical
  # triggers are pod evictions, OOM kills, the multi-attach PVC
  # disaster. Each orphan registration locks its branch ref ("refusing
  # to fetch into branch X checked out at <orphan path>"), which
  # blocks every subsequent fetch + every rebase Run on that branch.
  # Cheap to run on every setup — bounded by the number of worktrees
  # for one repo, which is bounded by concurrent Runs.
  def sweep_orphan_worktrees
    list = @git.run("worktree", "list", "--porcelain", chdir: bare_clone_path.to_s) rescue ""
    current = nil
    worktrees = []
    list.each_line do |l|
      if l.start_with?("worktree ")
        current = { path: l.sub("worktree ", "").chomp }
        worktrees << current
      elsif current && l.start_with?("branch ")
        current[:branch] = l.sub("branch ", "").chomp
      end
    end

    worktrees.each do |w|
      # Worktree directory names are pure integer run IDs (per
      # JobWorkspace#initialize: `data_root/worktrees/<run_id>`).
      # Bare clone path basename is `<repo_id>.git`. Filtering on
      # basename matching /\A\d+\z/ excludes the bare safely and
      # avoids macOS /var ↔ /private/var realpath confusion.
      basename = File.basename(w[:path])
      next unless basename =~ /\A\d+\z/
      run_id = basename.to_i
      run = Run.find_by(id: run_id)
      orphan = run.nil? || %w[succeeded failed cancelled].include?(run.state)
      next unless orphan

      @git.run("worktree", "remove", "--force", w[:path], chdir: bare_clone_path.to_s) rescue nil
      FileUtils.rm_rf(w[:path]) if File.exist?(w[:path])
    end

    # Catch any registrations whose directory disappeared without
    # going through git worktree remove.
    @git.run("worktree", "prune", chdir: bare_clone_path.to_s) rescue nil
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
