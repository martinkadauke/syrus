class MergeabilityRecorder
  def self.record_github!(job:, pr:, checked_at: Time.current)
    attrs = {
      pr_mergeable: mergeable(pr),
      pr_mergeable_checked_at: checked_at,
      github_mergeable: mergeable(pr),
      github_mergeable_state: mergeable_state(pr),
      mergeability_head_sha: pr_head_sha(pr),
      mergeability_base_sha: pr_base_sha(pr),
      mergeability_base_ref: pr_base_ref(pr),
      mergeability_checked_at: checked_at
    }

    job.update!(attrs)
  end

  def self.record_local!(job:, result:, checked_at: Time.current)
    job.update!(
      local_mergeable: result.mergeable,
      local_mergeable_state: result.state,
      local_mergeability_head_sha: result.head_sha,
      local_mergeability_base_sha: result.base_sha,
      local_mergeability_checked_at: checked_at
    )
  end

  def self.github_state(pr)
    mergeable_state(pr)
  end

  def self.head_sha(pr)
    pr_head_sha(pr)
  end

  def self.base_sha(pr)
    pr_base_sha(pr)
  end

  def self.base_ref(pr)
    pr_base_ref(pr)
  end

  def self.mergeable(pr)
    return unless pr&.respond_to?(:mergeable)

    pr.mergeable
  end
  private_class_method :mergeable

  def self.mergeable_state(pr)
    return unless pr&.respond_to?(:mergeable_state)

    pr.mergeable_state
  end
  private_class_method :mergeable_state

  def self.pr_head_sha(pr)
    pr&.head&.sha.to_s.presence
  end
  private_class_method :pr_head_sha

  def self.pr_base_sha(pr)
    pr&.base&.sha.to_s.presence
  end
  private_class_method :pr_base_sha

  def self.pr_base_ref(pr)
    pr&.base&.ref.to_s.presence
  end
  private_class_method :pr_base_ref
end
