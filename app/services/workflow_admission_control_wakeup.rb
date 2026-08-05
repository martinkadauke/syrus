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
      .where("artifacts LIKE ? OR artifacts LIKE ?", "%#{StepDispatcher::ADMISSION_BLOCK_REASON}%", '%"pause_reason"%')
      .find_each do |workflow|
        next unless workflow.artifact("start_blocked_reason") == StepDispatcher::ADMISSION_BLOCK_REASON ||
                    workflow.artifact("pause_reason").present?

        WorkflowPhaseAdmissionJob.perform_later(workflow.id)
      end
  end
end
