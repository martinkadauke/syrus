class RebaseLoopGuard
  BLOCK_REASON = "waiting for GitHub mergeability after no-op rebase".freeze

  def self.latest_noop_rebase(job)
    job.workflows
       .where(trigger_kind: "rebase", state: "succeeded")
       .reorder(id: :desc)
       .detect { |workflow| noop_result?(workflow.artifact("auto_rebase_result")) }
  end

  def self.waiting_after_noop?(job)
    job.pr_mergeable == false && latest_noop_rebase(job).present?
  end

  def self.noop_rebase_for?(job:, pr:)
    workflow = latest_noop_rebase(job)
    return false unless workflow

    result = workflow.artifact("auto_rebase_result")
    post_sha = result["post_sha"].presence
    base_sha = result["base_sha"].presence
    return false if post_sha.blank? || base_sha.blank?

    post_sha == pr_head_sha(pr) && base_sha == pr_base_sha(pr)
  end

  def self.noop_result?(result)
    result.is_a?(Hash) && result["changed"] == false && result["reason"] == "rebased"
  end
  private_class_method :noop_result?

  def self.pr_head_sha(pr)
    pr.head&.sha.to_s.presence
  end
  private_class_method :pr_head_sha

  def self.pr_base_sha(pr)
    pr.base&.sha.to_s.presence
  end
  private_class_method :pr_base_sha
end
