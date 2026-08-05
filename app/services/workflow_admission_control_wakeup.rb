class WorkflowAdmissionControlWakeup
  def self.call = new.call

  def call
    wake_deferred_workflows
    LandingQueueProcessorJob.perform_later
  end

  private

  def wake_deferred_workflows
    Workflow
      .where(state: %w[queued running])
      .where("artifacts LIKE ?", "%#{StepDispatcher::ADMISSION_BLOCK_REASON}%")
      .find_each do |workflow|
        next unless workflow.artifact("start_blocked_reason") == StepDispatcher::ADMISSION_BLOCK_REASON

        WorkflowPhaseAdmissionJob.perform_later(workflow.id)
      end
  end
end
