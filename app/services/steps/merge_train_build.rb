module Steps
  # Builds the integration branch: start at the base tip, then integrate
  # each member's branch in topological order with `git merge --no-ff`.
  # A clean merge is the fast path; on a textual conflict the agent
  # resolves it in the working tree and Syrus completes the merge. Only
  # an unresolvable conflict (or agent failure) fails the whole Epic
  # attempt. Leaves HEAD on the integration branch so the prepare /
  # grader / landing_fix steps operate on the combined tree.
  class MergeTrainBuild < Base
    include MergeTrainStep

    def call
      train = merge_train
      members = train.member_jobs
      raise StepFailed, "merge_train: no members to build" if members.empty?

      workspace.setup
      @chdir = workspace.path.to_s
      @git = streaming_git(env: { "GIT_TERMINAL_PROMPT" => "0" })
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

      sha = @git.run("rev-parse", "HEAD", chdir: @chdir).strip
      train.update!(integration_branch: @integration, integration_sha: sha, state: "grading")
      log("merge_train: built #{@integration} at #{sha.first(9)} (#{members.size} member(s) integrated)")
    end

    private

    def integrate!(member, branch)
      @git.run(
        "merge", "--no-ff",
        "-m", "Integrate ##{member.issue_number || member.id} (#{branch})",
        "FETCH_HEAD",
        chdir: @chdir
      )
    rescue GitRunner::GitError => e
      raise unless merge_conflict?
      resolve_conflict_with_agent!(member, branch, e)
    end

    # A failed `git merge` is a conflict (vs. a real git error) when the
    # merge is in progress with unmerged paths (MERGE_HEAD present).
    def merge_conflict?
      @git.run("rev-parse", "-q", "--verify", "MERGE_HEAD", chdir: @chdir)
      true
    rescue GitRunner::GitError
      false
    end

    def resolve_conflict_with_agent!(member, branch, error)
      log("merge_train: conflict integrating #{branch}; invoking agent to resolve", kind: "system")
      run.update!(prompt: conflict_prompt(member, branch))
      run_agent(prompt: run.prompt)

      stage_and_verify_resolution!(branch)
      @git.run("commit", "--no-edit", chdir: @chdir)
      log("merge_train: agent resolved conflict integrating #{branch}", kind: "system")
    rescue Steps::Base::StepFailed
      abort_merge!
      raise
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

    def abort_merge!
      @git.run("merge", "--abort", chdir: @chdir)
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
