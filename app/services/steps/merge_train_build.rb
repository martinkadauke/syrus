module Steps
  # Builds the integration branch: start at the base tip, then integrate
  # each member's branch in topological order by REBASING the member's
  # commits onto the growing integration tip.
  #
  # The mechanical `git rebase` is always tried first — a member that
  # only needs to move forward (or whose changes don't overlap) replays
  # cleanly with no agent. Only when git stops on a real conflict does
  # the agent resolve it in the working tree; Syrus then continues the
  # rebase. git's patch-id detection skips commits already integrated, so
  # stacked members replay only their own commits. An unresolvable
  # conflict (or agent failure) aborts and fails the whole Epic attempt.
  # Leaves HEAD on the integration branch for the prepare / grader /
  # landing_fix steps.
  class MergeTrainBuild < Base
    include MergeTrainStep

    # Safety bound on per-member conflict iterations (a rebase can stop
    # once per replayed commit). Far above any real member.
    MAX_CONFLICT_STEPS = 100

    def call
      train = merge_train
      members = train.member_jobs
      raise StepFailed, "merge_train: no members to build" if members.empty?

      workspace.setup
      @chdir = workspace.path.to_s
      @git = streaming_git(env: { "GIT_TERMINAL_PROMPT" => "0", "GIT_EDITOR" => "true" })
      @integration = train.integration_branch.presence || "syrus/merge-train-epic-#{train.epic_id}-#{train.id}"

      @git.run("fetch", "origin", train.base_branch, chdir: @chdir)
      @git.run("checkout", "-B", @integration, "FETCH_HEAD", chdir: @chdir)
      log("merge_train: integration branch #{@integration} started at #{train.base_branch}")

      members.each do |member|
        branch = member.branch_name
        raise StepFailed, "merge_train: member Job ##{member.id} has no branch" if branch.blank?

        @git.run("fetch", "origin", branch, chdir: @chdir)
        integrate!(member, branch)
      end

      @git.run("checkout", @integration, chdir: @chdir)
      sha = @git.run("rev-parse", "HEAD", chdir: @chdir).strip
      train.update!(integration_branch: @integration, integration_sha: sha, state: "grading")
      log("merge_train: built #{@integration} at #{sha.first(9)} (#{members.size} member(s) integrated)")
    end

    private

    # Replay the member's commits onto the current integration tip, then
    # fast-forward the integration branch to the result.
    def integrate!(member, branch)
      temp = "__mt_member_#{member.id}"
      @git.run("checkout", "-B", temp, "FETCH_HEAD", chdir: @chdir)
      rebase_member!(member, branch)
      @git.run("checkout", @integration, chdir: @chdir)
      @git.run("merge", "--ff-only", temp, chdir: @chdir)
      @git.run("branch", "-D", temp, chdir: @chdir)
    end

    # Mechanical attempt first: `git rebase <integration>` replays the
    # checked-out member branch's commits onto the integration tip. Only
    # on a genuine conflict (rebase stops mid-flight) does the agent step in.
    def rebase_member!(member, branch)
      @git.run("rebase", @integration, chdir: @chdir)
    rescue GitRunner::GitError
      raise unless rebase_in_progress?

      resolve_rebase_with_agent!(member, branch)
    end

    def resolve_rebase_with_agent!(member, branch)
      log("merge_train: conflict rebasing #{branch} onto integration; invoking agent to resolve", kind: "system")
      run.update!(prompt: conflict_prompt(member, branch))

      steps = 0
      loop do
        raise StepFailed, "merge_train: too many conflict iterations integrating #{branch}" if (steps += 1) > MAX_CONFLICT_STEPS

        run_agent(prompt: run.prompt)
        stage_and_verify_resolution!(branch)
        continue_rebase!
        break unless rebase_in_progress?
      end
      log("merge_train: agent resolved conflicts integrating #{branch}", kind: "system")
    rescue Steps::Base::StepFailed
      abort_rebase!
      raise
    end

    # `git rebase --continue` after the conflict is staged. A non-zero
    # exit with the rebase still in progress means the *next* replayed
    # commit conflicted — the caller loops and resolves again. A non-zero
    # exit with no rebase in progress is a real error.
    def continue_rebase!
      @git.run("rebase", "--continue", chdir: @chdir)
    rescue GitRunner::GitError
      raise unless rebase_in_progress?
    end

    def stage_and_verify_resolution!(branch)
      @git.run("add", "-A", chdir: @chdir)

      unmerged = @git.run("ls-files", "-u", chdir: @chdir).to_s.strip
      raise StepFailed, "merge_train: agent left unmerged paths integrating #{branch}" unless unmerged.empty?

      # `git diff --cached --check` exits non-zero if any staged content
      # still contains conflict markers.
      begin
        @git.run("diff", "--cached", "--check", chdir: @chdir)
      rescue GitRunner::GitError
        raise StepFailed, "merge_train: agent left unresolved conflict markers integrating #{branch}"
      end
    end

    # A rebase is in progress (stopped at a conflict) when REBASE_HEAD
    # exists — same trick as MERGE_HEAD, and stubbable in specs.
    def rebase_in_progress?
      @git.run("rev-parse", "-q", "--verify", "REBASE_HEAD", chdir: @chdir)
      true
    rescue GitRunner::GitError
      false
    end

    def abort_rebase!
      @git.run("rebase", "--abort", chdir: @chdir)
    rescue GitRunner::GitError
      nil
    end

    def conflict_prompt(member, branch)
      Prompts::MergeTrainConflict.new(
        repo_slug: repository.slug,
        member_branch: branch,
        integration_branch: @integration,
        pr_number: member.pr_number
      ).to_s
    end
  end
end
