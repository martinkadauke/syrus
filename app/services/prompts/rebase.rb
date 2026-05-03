module Prompts
  # Prompt for `rebase` Runs. Tells the agent the branch is behind base
  # and needs to be rebased so the PR becomes mergeable again. Strict:
  # *no functional changes* — only conflict resolution. The Run's job is
  # to keep the PR mergeable, not to revisit the work.
  class Rebase
    def initialize(repo_slug:, branch_name:, base_branch:, pr_number:)
      @repo_slug   = repo_slug
      @branch_name = branch_name
      @base_branch = base_branch
      @pr_number   = pr_number
    end

    def to_s
      body = <<~PROMPT.strip
        This is a **rebase** run. The pull request `#{@repo_slug}##{@pr_number}` from branch
        `#{@branch_name}` onto `#{@base_branch}` is no longer mergeable — its branch has
        fallen behind base and conflicts with it.

        Your job is to make it mergeable again. Specifically:

        1. Run `git fetch origin #{@base_branch}` so you have the latest base.
        2. Run `git rebase origin/#{@base_branch}` (you are already on `#{@branch_name}`).
        3. If conflicts come up, **resolve them mechanically** — preserve both intents
           where possible, prefer minimal edits, never delete code that looks like real
           work just to make the rebase clean.
        4. Continue the rebase (`git add <resolved files> && git rebase --continue`)
           until it completes.
        5. Do NOT make functional changes beyond what conflict resolution requires.
        6. Do NOT run tests, lint, formatters, or anything else that mutates files.
           If they catch real bugs introduced by the conflict resolution, that's
           a separate Run's problem.
        7. If you cannot resolve a conflict mechanically (the two sides genuinely
           disagree on intent), abort the rebase (`git rebase --abort`) and explain
           in `submit_summary`. Do NOT push a half-rebased branch.

        Syrus will force-push the rebased branch to origin once you finish — your
        only job is to leave the working tree on a clean rebased HEAD.
      PROMPT

      [ body, GitSafety::TEXT ].join("\n\n")
    end
  end
end
