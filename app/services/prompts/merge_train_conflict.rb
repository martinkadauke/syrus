module Prompts
  # Prompt for resolving a textual conflict while integrating an Epic's
  # member branch into the merge-train integration branch. Reuses the
  # rebase skill's git-conflict-resolution instructions; the only
  # difference from a rebase is that Syrus completes the merge commit
  # afterward, so the agent must resolve the conflict markers in the
  # working tree and must NOT commit, push, or run other git commands.
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
        This is an **Epic merge-train integration** run. Syrus is merging the member
        pull request `#{@repo_slug}##{@pr_number}` (branch `#{@member_branch}`) into the
        shared integration branch `#{@integration_branch}`, and `git merge` stopped with
        conflicts.

        Resolve every conflict in the working tree so the combined result is correct —
        keep the intent of BOTH the member's change and everything already on the
        integration branch. Edit the conflicted files to remove all conflict markers.

        IMPORTANT: do NOT run `git add`, `git commit`, `git merge --continue`,
        `git rebase`, `git push`, or `git checkout`. Syrus completes and commits the
        merge after you finish. Only edit files to resolve the conflicts.
      CONTEXT
      SkillLoader.render(SKILL_FILE, context)
    end
  end
end
