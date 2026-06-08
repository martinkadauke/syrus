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

  # Did this Job pass required graders at some point (any head/base)?
  # Used by the opt-in clean-rebase carry-forward (Steps::ForcePush) to
  # decide whether there's a green grade worth carrying across a clean
  # rebase under Repository#trust_clean_rebase_grade.
  def self.green_validation_present?(job)
    recorded_workflows(job).any? do |workflow|
      artifact = workflow.artifact(ARTIFACT_KEY)
      artifact.is_a?(Hash) && artifact["required_graders_passed"] == true
    end
  end

  # auto_merge workflows write the validation when graders pass; rebase
  # workflows write it when carrying a green grade across a clean rebase
  # (opt-in). Both are valid sources for skip-on-revalidation.
  def self.recorded_workflows(job)
    job.workflows.where(trigger_kind: %w[ auto_merge rebase ]).reorder(id: :desc)
  end
  private_class_method :recorded_workflows

  def self.matching_artifact(job, head_sha:, base_sha:)
    recorded_workflows(job).detect do |workflow|
      artifact = workflow.artifact(ARTIFACT_KEY)
      artifact.is_a?(Hash) &&
        artifact["required_graders_passed"] == true &&
        artifact["head_sha"] == head_sha &&
        artifact["base_sha"] == base_sha
    end&.artifact(ARTIFACT_KEY)
  end
  private_class_method :matching_artifact
end
