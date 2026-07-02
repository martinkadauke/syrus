class BranchDivergenceRecovery
  Result = Data.define(:error) do
    def success? = error.blank?
  end

  def self.force_push!(...) = new(...).force_push!
  def self.discard!(...) = new(...).discard!

  def initialize(workflow:, user:)
    @workflow = workflow
    @job = workflow.job
    @user = user
  end

  def force_push!
    return failure("No branch divergence was recorded for this workflow.") unless divergence
    return failure("Unapprove before replacing the PR branch.") if job.approved? || job.landing?
    return failure("Closed Jobs cannot replace PR branches.") if job.closed?
    return failure("Workspace already cleaned up - retry from the current PR branch instead.") unless workspace_path.directory?
    return failure("Cannot safely force-push without the observed remote branch SHA.") if remote_sha.blank?

    git.run(
      "push",
      "--force-with-lease=refs/heads/#{branch}:#{remote_sha}",
      push_url,
      "HEAD:refs/heads/#{branch}",
      chdir: workspace_path.to_s
    )
    record_recovery!("force_pushed")
    restore_job_to_implemented_if_possible!
    Result.new(error: nil)
  rescue GitRunner::GitError => e
    failure("Force-push failed: #{e.message}")
  end

  def discard!
    return failure("No branch divergence was recorded for this workflow.") unless divergence

    record_recovery!("discarded")
    restore_job_to_implemented_if_possible!
    Result.new(error: nil)
  end

  private

  attr_reader :workflow, :job, :user

  def divergence
    @divergence ||= workflow.artifact("branch_divergence").presence
  end

  def branch
    divergence["branch"].presence || job.branch_name
  end

  def remote_sha
    divergence["remote_sha"].presence
  end

  def workspace_path
    WorkflowWorkspace.path_for(workflow)
  end

  def push_url
    token = GithubClient.for(repository: job.repository, user: job.user).access_token
    job.repository.authenticated_push_url(token)
  end

  def git
    @git ||= GitRunner.new
  end

  def record_recovery!(action)
    workflow.set_artifact!("branch_divergence_recovery", {
      "action" => action,
      "user_id" => user.id,
      "at" => Time.current.iso8601
    })
    latest_run = workflow.runs.order(:created_at).last
    JobLog.append!(run: latest_run, chunk: "branch divergence recovery: #{action}", kind: "system") if latest_run
  end

  def restore_job_to_implemented_if_possible!
    return unless job.failed? && job.pr_number.present?

    StateTransition.with_source("operator") do
      job.retry_after_failure! if job.may_retry_after_failure?
      job.mark_implemented! if job.may_mark_implemented?
      job.save!
    end
  end

  def failure(message)
    Result.new(error: message)
  end
end
