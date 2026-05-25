class RebaseTarget
  BASE_BRANCH_ARTIFACT = "rebase_base_branch"
  BASE_SHA_ARTIFACT = "rebase_base_sha"

  def self.branch_for(job:, workflow: nil)
    workflow&.artifact(BASE_BRANCH_ARTIFACT).presence || job.effective_base_branch
  end

  def self.artifacts(artifacts: nil, pr: nil, base_branch: nil)
    merged = (artifacts || {}).dup
    branch = base_branch.presence || pr&.base&.ref.to_s.presence
    sha = pr&.base&.sha.to_s.presence

    merged[BASE_BRANCH_ARTIFACT] = branch if branch.present?
    merged[BASE_SHA_ARTIFACT] = sha if sha.present?
    merged.presence
  end
end
