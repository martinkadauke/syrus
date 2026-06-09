module Prompts
  # Prompt for resolving a textual conflict while integrating an Epic's
  # member branch into the merge-train integration branch. Syrus rebases
  # the member's commits onto the integration tip; when git stops on a
  # conflict, the agent resolves the markers in the working tree and Syrus
  # continues the rebase. Reuses the rebase skill's conflict-resolution
  # instructions; the agent must NOT run git commands itself.
  class MergeTrainConflict
    SKILL_FILE = Rails.root.join(".claude/skills/rebase/SKILL.md").freeze

    def initialize(repo_slug:, member_branch:, integration_branch:, pr_number:)
      @repo_slug = repo_slug
      @member_branch = member_branch
      @integration_branch = integration_branch
      @pr_number = pr_number
    end

    def to_s
      context = <<~CONTEXT.strip
        This is an **Epic merge-train integration** run. Syrus is rebasing the member
        pull request `#{@repo_slug}##{@pr_number}` (branch `#{@member_branch}`) onto the
        shared integration branch `#{@integration_branch}`, and `git rebase` stopped on
        a conflict.

        Resolve every conflict in the working tree so the combined result is correct —
        keep the intent of BOTH the member's change and everything already on the
        integration branch. Edit the conflicted files to remove all conflict markers.

        IMPORTANT: do NOT run `git add`, `git commit`, `git rebase --continue`,
        `git push`, or `git checkout`. Syrus continues the rebase after you finish.
        Only edit files to resolve the conflicts.
      CONTEXT
      SkillLoader.render(SKILL_FILE, context)
    end
  end
end
