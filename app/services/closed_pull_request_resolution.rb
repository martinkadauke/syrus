class ClosedPullRequestResolution
  def self.reason(job:, pr:, client:, git: nil)
    new(job: job, pr: pr, client: client, git: git).reason
  end

  def initialize(job:, pr:, client:, git: nil)
    @job = job
    @pr = pr
    @client = client
    @git = git
  end

  def reason
    return "pr_merged" if merged?
    return "no_changes" if branch_patch_already_on_base?

    "pr_closed"
  end

  private

  def merged?
    @pr.respond_to?(:merged) && @pr.merged
  end

  def branch_patch_already_on_base?
    BranchPatchPresence.no_unique_commits?(job: @job, pr: @pr, client: @client, git: @git)
  end
end
