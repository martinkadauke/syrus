module Steps
  # Builds the integration branch: start at the base tip, then integrate
  # each member's branch in topological order by REBASING the member's
  # commits onto the growing integration tip.
  #
  # The mechanical `git rebase` runs first — a member that only needs to
  # move forward (or whose changes don't overlap) replays cleanly with no
  # agent. On a genuine conflict, Syrus leaves that rebase (already
  # targeting the integration branch) in progress and hands the agent ONE
  # task: resolve the conflicts and finish the in-progress rebase. Syrus
  # then verifies the outcome deterministically — the rebase must be
  # finished, the worktree clean, and the integration branch an ancestor
  # of the result — and fast-forwards the integration branch.
  #
  # Why agent-owns-completion rather than agent-edits-then-Syrus-continues:
  # the agent (esp. codex) autonomously runs git, so Syrus can't assume the
  # rebase is still mid-flight after the agent runs. Tolerating completion
  # and verifying the end state is robust to that; a single agent call also
  # avoids a duplicate claude_session capture.
  class MergeTrainBuild < Base
    include MergeTrainStep

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

    # Replay the member's commits onto the integration tip on a scratch
    # branch, then fast-forward the integration branch to the result.
    def integrate!(member, branch)
      temp = "__mt_member_#{member.id}"
      @git.run("checkout", "-B", temp, "FETCH_HEAD", chdir: @chdir)
      rebase_member!(member, branch)
      verify_rebased!(branch, temp)
      @git.run("checkout", @integration, chdir: @chdir)
      @git.run("merge", "--ff-only", temp, chdir: @chdir)
      @git.run("branch", "-D", temp, chdir: @chdir)
    end

    # Mechanical attempt first; only a genuine conflict (rebase stops with
    # REBASE_HEAD set) escalates to the agent.
    def rebase_member!(member, branch)
      @git.run("rebase", @integration, chdir: @chdir)
    rescue GitRunner::GitError
      raise unless rebase_in_progress?

      resolve_with_agent!(member, branch)
    end

    # Hand the in-progress (correctly-targeted) rebase to the agent to
    # resolve and complete. Single agent call.
    def resolve_with_agent!(member, branch)
      log("merge_train: conflict integrating #{branch}; agent resolving the in-progress rebase", kind: "system")
      run.update!(prompt: conflict_prompt(member, branch))
      run_agent(prompt: run.prompt)

      if rebase_in_progress?
        abort_rebase!
        raise StepFailed, "merge_train: agent did not finish the rebase integrating #{branch}"
      end
    end

    # Deterministic verification that the member was correctly integrated:
    # no rebase left in progress, a clean worktree, and the integration
    # branch is an ancestor of the rebased result (i.e. it was rebased onto
    # the integration tip, not master or anything else).
    def verify_rebased!(branch, temp)
      @git.run("checkout", temp, chdir: @chdir)

      status = @git.run("status", "--porcelain", chdir: @chdir).to_s.strip
      raise StepFailed, "merge_train: integrating #{branch} left a dirty worktree" unless status.empty?

      begin
        @git.run("merge-base", "--is-ancestor", @integration, temp, chdir: @chdir)
      rescue GitRunner::GitError
        raise StepFailed, "merge_train: #{branch} was not rebased onto the integration branch"
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
