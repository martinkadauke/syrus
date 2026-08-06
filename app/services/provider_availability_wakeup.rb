class ProviderAvailabilityWakeup
  def self.call(provider:, user:)
    new(provider: provider, user: user).call
  end

  def initialize(provider:, user:)
    @provider = provider.to_s
    @user = user
  end

  def call
    provider_paused_workflows.each do |workflow|
      WorkflowPhaseAdmissionJob.perform_later(workflow.id)
    end
    LandingQueueProcessorJob.perform_later if provider_paused_workflows.any?(&:landing_workflow?)
  end

  private

  attr_reader :provider, :user

  def workflows
    Workflow
      .where(user_id: user.id, agent_provider: provider, state: %w[queued running])
      .where("artifacts LIKE ?", "%#{StepDispatcher::PROVIDER_AVAILABILITY_BLOCK_REASON}%")
  end

  def provider_paused_workflows
    @provider_paused_workflows ||= workflows.to_a.select do |workflow|
      workflow.artifact("start_blocked_reason") == StepDispatcher::PROVIDER_AVAILABILITY_BLOCK_REASON ||
        workflow.artifact("pause_reason") == StepDispatcher::PROVIDER_AVAILABILITY_BLOCK_REASON
    end
  end
end
