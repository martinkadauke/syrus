class ResumeWorkflowEnqueuer
  Result = Data.define(:run, :workflow, :error) do
    def success? = run.present?
  end

  def self.call(...) = new(...).call

  def initialize(job:, source_run:)
    @job = job
    @source_run = source_run
  end

  def call
    return failure("Source Run not found.") unless source_run
    return failure("Source Run does not belong to this Job.") unless source_run.job_id == job.id
    return failure("Only failed or cancelled Runs are resumable.") unless source_run.failed? || source_run.cancelled?
    return failure("A Run is already in progress - wait for it to finish.") if job.any_active_run?

    session = source_run.claude_session
    return failure("No agent session captured for that Run - try Retry instead.") unless session

    if job.failed? && job.may_retry_after_failure?
      job.retry_after_failure!
      job.save!
    end

    workflow = Workflows::Resume.instantiate(job: job, agent_provider: session.provider)
    run = StepDispatcher.start_workflow(
      workflow,
      parent_session_id: session.session_id,
      prompt: Prompts::Resume.new.to_s
    )

    return failure("Resume workflow could not be started.") unless run

    Result.new(run: run, workflow: workflow, error: nil)
  end

  private

  attr_reader :job, :source_run

  def failure(message)
    Result.new(run: nil, workflow: nil, error: message)
  end
end
