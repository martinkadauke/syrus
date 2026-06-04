module Steps
  # Agentic final pass before auto-merge. Runs on the approved PR
  # branch immediately before graders and the merge API call, so
  # post-rebase or post-review integration failures can be fixed on
  # the exact tree Syrus is about to land.
  class LandingFix < Base
    def call
      perform_agentic_change_step(
        log_message: "invoking agent for landing_fix step (workflow ##{workflow.id}, auto_merge)",
        commit_message: "Syrus pre-merge fix"
      ) do
        run.update!(prompt: compose_prompt) if run.prompt.blank?
      end
    end

    private

    def compose_prompt
      issue = job.issue? ? fetch_issue : job.synthetic_issue
      prompt = Prompts::LandingFix.new(
        issue: issue,
        pr_number: job.pr_number,
        repo_slug: repository.slug,
        branch_name: job.branch_name,
        recent_commits: recent_branch_commits
      ).to_s

      return prompt unless run.iteration > 1

      [
        prompt,
        Prompts::GradeFailureFeedback.new(
          iterations: workflow.artifacts.fetch("iterations", [])
        ).to_s
      ].join("\n\n")
    end

    def fetch_issue
      GithubClient.for(repository: repository, user: job.user).fetch_issue(repository.slug, job.issue_number)
    end

    def recent_branch_commits(limit: 10)
      workspace.setup
      raw = GitRunner.new.run(
        "log",
        "--no-merges",
        "-n", limit.to_s,
        "--format=%H%x09%s",
        "HEAD",
        chdir: workspace.path.to_s
      )
      raw.each_line.map do |line|
        sha, subject = line.chomp.split("\t", 2)
        { sha: sha, subject: subject }
      end
    rescue StandardError => e
      log("[landing_fix] could not read commit history for prompt: #{e.class}: #{e.message}")
      []
    end
  end
end
