module Prompts
  # Prompt for resolving a rebase conflict discovered while a follow-up
  # workflow was trying to push to an existing PR branch. The workspace is
  # already in the conflicted rebase state when the agent starts.
  class PushRebase
    def initialize(repo_slug:, branch_name:, remote_ref:, pr_number:)
      @repo_slug = repo_slug
      @branch_name = branch_name
      @remote_ref = remote_ref
      @pr_number = pr_number
    end

    def to_s
      [
        context,
        instructions,
        GitSafety::TEXT
      ].join("\n\n---\n\n")
    end

    private

    def context
      <<~SECTION.strip
        This is a rebase recovery run for PR `#{@repo_slug}##{@pr_number}` on branch `#{@branch_name}`.

        Syrus addressed follow-up feedback locally, but before it could push,
        the remote PR branch advanced. Syrus fetched the current remote branch
        as `#{@remote_ref}` and started rebasing the local follow-up commit onto it.
        That rebase has conflicts and is already in progress in this workspace.
      SECTION
    end

    def instructions
      <<~SECTION.strip
        Resolve the in-progress rebase mechanically:

        - Inspect `git status` to see the conflicted files.
        - Preserve both the remote branch changes and the local follow-up feedback changes where possible.
        - Make the smallest edits needed to resolve the conflicts.
        - Run `git add <resolved files>` and `git rebase --continue`.
        - Continue until the rebase is complete and the working tree is clean.
        - Do not broaden the feature or change unrelated code.
        - Do not push.

        If the conflict cannot be resolved mechanically, leave a clear explanation in your final message and do not invent unrelated behavior.
      SECTION
    end
  end
end
