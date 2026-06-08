module Steps
  # Builds the integration branch: start at the base tip, then merge each
  # member's branch in topological order. A textual conflict fails the
  # whole Epic attempt (v1 — no agent-assisted build resolution); the
  # fix loop downstream handles *logical* conflicts on the integrated
  # tree. Leaves HEAD on the integration branch so the prepare / grader /
  # landing_fix steps operate on the combined tree.
  class MergeTrainBuild < Base
    include MergeTrainStep

    def call
      train = merge_train
      members = train.member_jobs
      raise StepFailed, "merge_train: no members to build" if members.empty?

      workspace.setup
      chdir = workspace.path.to_s
      git = streaming_git(env: { "GIT_TERMINAL_PROMPT" => "0" })
      integration = train.integration_branch.presence || "syrus/merge-train-epic-#{train.epic_id}-#{train.id}"

      git.run("fetch", "origin", train.base_branch, chdir: chdir)
      git.run("checkout", "-B", integration, "FETCH_HEAD", chdir: chdir)
      log("merge_train: integration branch #{integration} started at #{train.base_branch}")

      members.each do |member|
        branch = member.branch_name
        raise StepFailed, "merge_train: member Job ##{member.id} has no branch" if branch.blank?

        git.run("fetch", "origin", branch, chdir: chdir)
        integrate!(git, chdir, member, branch)
      end

      sha = git.run("rev-parse", "HEAD", chdir: chdir).strip
      train.update!(integration_branch: integration, integration_sha: sha, state: "grading")
      log("merge_train: built #{integration} at #{sha.first(9)} (#{members.size} member(s) integrated)")
    end

    private

    def integrate!(git, chdir, member, branch)
      git.run(
        "merge", "--no-ff",
        "-m", "Integrate ##{member.issue_number || member.id} (#{branch})",
        "FETCH_HEAD",
        chdir: chdir
      )
    rescue GitRunner::GitError => e
      begin
        git.run("merge", "--abort", chdir: chdir)
      rescue GitRunner::GitError
        nil
      end
      raise StepFailed, "merge_train: textual conflict integrating ##{member.issue_number || member.id} (#{branch}): #{e.message.to_s[0, 200]}"
    end
  end
end
