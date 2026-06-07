class LandingValidationCache
  ARTIFACT_KEY = "landing_validation".freeze

  def self.record!(workflow:, head_sha:, base_sha:, base_ref:)
    workflow.set_artifact!(
      ARTIFACT_KEY,
      {
        "required_graders_passed" => true,
        "head_sha" => head_sha.to_s.presence,
        "base_sha" => base_sha.to_s.presence,
        "base_ref" => base_ref.to_s.presence,
        "checked_at" => Time.current.iso8601
      }.compact
    )
  end

  def self.valid_for?(job:, pr:)
    head_sha = MergeabilityRecorder.head_sha(pr)
    base_sha = MergeabilityRecorder.base_sha(pr)
    return false if head_sha.blank? || base_sha.blank?

    matching_artifact(job, head_sha: head_sha, base_sha: base_sha).present?
  end

  def self.matching_artifact(job, head_sha:, base_sha:)
    job.workflows.where(trigger_kind: "auto_merge").reorder(id: :desc).detect do |workflow|
      artifact = workflow.artifact(ARTIFACT_KEY)
      artifact.is_a?(Hash) &&
        artifact["required_graders_passed"] == true &&
        artifact["head_sha"] == head_sha &&
        artifact["base_sha"] == base_sha
    end&.artifact(ARTIFACT_KEY)
  end
  private_class_method :matching_artifact
end
