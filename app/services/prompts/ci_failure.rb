module Prompts
  # Prompt for `ci_failure` Runs. Tells the agent which checks went red
  # on the current PR head, includes the GitHub-provided summary text,
  # and asks for a fix on the existing branch. Same scope rule as
  # PrFeedback: no functional drift, just make the failing checks pass.
  class CiFailure
    MAX_CHECKS = 5
    MAX_SUMMARY_BYTES = 2_000

    def initialize(issue:, pr_number:, repo_slug:, branch_name:, head_sha:, failed_checks:)
      @issue        = issue
      @pr_number    = pr_number
      @repo_slug    = repo_slug
      @branch_name  = branch_name
      @head_sha     = head_sha
      @failed_checks = failed_checks
    end

    def to_s
      <<~PROMPT.strip
        CI is failing on PR `#{@repo_slug}##{@pr_number}` (branch `#{@branch_name}` at `#{@head_sha[0..6]}`). Fix the failing checks.

        # Original issue
        Title: #{@issue.title}

        Body:
        #{@issue.body.to_s.strip.presence || '(empty)'}

        # Failing checks (#{@failed_checks.size} total, showing up to #{MAX_CHECKS})
        #{render_checks}

        # How to act

        - Read each failing check's summary above. The summary is what
          GitHub showed in the PR's "Checks" tab.
        - Reproduce the failure locally where possible (run the test,
          run the linter, run the build). The repo is checked out at
          the failing commit.
        - Fix the code so the checks pass. Do **not** silence them by
          deleting tests, disabling linters, or weakening assertions.
        - Stay scoped to the failure. Do not refactor unrelated code,
          do not bump dependency versions speculatively, do not
          rewrite history.
        - Commit the fix. Syrus will push to `#{@branch_name}`; CI
          will re-run. If you can't fix the failure (e.g. it's a flake
          or an environment issue outside the diff's scope), say so
          in `submit_summary` instead of pushing a noop.
      PROMPT
    end

    private

    def render_checks
      @failed_checks.first(MAX_CHECKS).map { |c| render_check(c) }.join("\n\n")
    end

    def render_check(check)
      summary = check[:summary].to_s.strip
      summary = "(no summary provided)" if summary.empty?
      summary = "#{summary[0, MAX_SUMMARY_BYTES]}\n…[truncated]" if summary.bytesize > MAX_SUMMARY_BYTES

      <<~BLOCK.strip
        ## #{check[:name]} — #{check[:conclusion]}
        URL: #{check[:html_url]}

        Summary:
        #{summary}
      BLOCK
    end
  end
end
