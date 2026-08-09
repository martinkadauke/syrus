class LandingValidationPrefetcher
  ARTIFACT_WORKFLOW_ID = "landing_validation_prefetch_workflow_id".freeze
  ARTIFACT_DISPATCHED_AT = "landing_validation_prefetch_dispatched_at".freeze

  def self.after_landing_graders_passed(workflow:)
    new(workflow).call
  end

  def initialize(workflow, git: GitRunner.new)
    @workflow = workflow
    @job = workflow.job
    @git = git
  end

  def call
    return unless Feature.landing_validation_prefetch_enabled?
    return unless workflow.trigger_kind == "auto_merge"
    return if workflow.artifact(ARTIFACT_WORKFLOW_ID).present?
    return unless job&.landing?

    candidate = next_candidate
    return unless candidate

    source = source_identity
    return unless source
    candidate_info = candidate_identity(candidate)

    workflow_to_start = nil
    Workflow.transaction do
      candidate.lock!
      workflow.lock!
      if workflow.artifact(ARTIFACT_WORKFLOW_ID).blank? &&
          !candidate.workflows.active.where(trigger_kind: "landing_validation").exists? &&
          candidate.approved?
        workflow_to_start = Workflows::LandingValidation.instantiate(
          job: candidate,
          artifacts: source.merge(candidate_info)
        )
        workflow.set_artifact!(ARTIFACT_WORKFLOW_ID, workflow_to_start.id)
        workflow.set_artifact!(ARTIFACT_DISPATCHED_AT, Time.current.iso8601)
      end
    end

    StepDispatcher.start_workflow(workflow_to_start) if workflow_to_start
    workflow_to_start
  rescue StandardError => e
    Rails.logger.warn("[LandingValidationPrefetcher] prefetch dispatch failed for Workflow ##{workflow.id}: #{e.class}: #{e.message}")
    nil
  end

  private

  attr_reader :workflow, :job, :git

  def next_candidate
    entries = LandingQueueProcessor.entries(Job.where(repository_id: job.repository_id))
    index = entries.index { |entry| entry.job_id == job.id }
    return if index.nil?

    entries[(index + 1)..]&.find do |entry|
      ordinary_auto_merge_candidate?(entry.job) && entry.eligible?
    end&.job
  end

  def ordinary_auto_merge_candidate?(candidate)
    return false unless candidate.approved?
    return false if candidate.external_pr?
    return false if candidate.pr_number.blank?
    return false if candidate.epic_id.present? && AppSetting.merge_train_enabled?
    return false if candidate.workflows.active.where(trigger_kind: "landing_validation").exists?

    true
  end

  def source_identity
    path = WorkflowWorkspace.path_for(workflow)
    return unless path.exist?

    head_sha = git.run("rev-parse", "HEAD", chdir: path.to_s).strip.presence
    tree_sha = git.run("rev-parse", "HEAD^{tree}", chdir: path.to_s).strip.presence
    return if head_sha.blank? || tree_sha.blank?

    {
      "prefetch_source_workflow_id" => workflow.id,
      "prefetch_source_job_id" => job.id,
      "prefetch_source_workspace_path" => path.to_s,
      "prefetch_source_head_sha" => head_sha,
      "prefetch_source_tree_sha" => tree_sha,
      "predicted_base_sha" => head_sha,
      "predicted_base_tree_sha" => tree_sha,
      "predicted_base_ref" => job.effective_base_branch.presence || job.repository.default_branch
    }
  rescue StandardError => e
    Rails.logger.warn("[LandingValidationPrefetcher] source identity failed for Workflow ##{workflow.id}: #{e.class}: #{e.message}")
    nil
  end

  def candidate_identity(candidate)
    pr_repo = candidate.effective_pr_repository
    client = GithubClient.for(repository: pr_repo, user: candidate.user)
    pr = client.pull_request(pr_repo.slug, candidate.pr_number, bypass_cache: true)

    {
      "prefetch_candidate_pr_number" => candidate.pr_number,
      "prefetch_candidate_head_sha" => MergeabilityRecorder.head_sha(pr),
      "prefetch_candidate_base_ref" => MergeabilityRecorder.base_ref(pr)
    }.compact
  rescue StandardError => e
    Rails.logger.warn("[LandingValidationPrefetcher] candidate identity failed for #{candidate.slug}: #{e.class}: #{e.message}")
    {}
  end
end
