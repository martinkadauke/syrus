class BranchDivergenceRecoveryJob < ApplicationJob
  queue_as :merges

  limits_concurrency to: 1, key: ->(workflow_id, _user_id) { "branch-divergence-recovery:#{workflow_id}" }

  def perform(workflow_id, user_id)
    workflow = Workflow.includes(:job).find_by(id: workflow_id)
    user = User.find_by(id: user_id)
    return unless workflow && user

    result = BranchDivergenceRecovery.force_push!(workflow: workflow, user: user)
    BranchDivergenceRecovery.record_failure!(workflow: workflow, user: user, message: result.error) unless result.success?
  ensure
    broadcast_update(workflow) if workflow
  end

  private

  def broadcast_update(workflow)
    job = workflow.job
    AppEvents.broadcast(
      user: job.user,
      type: "updated",
      resource: "job",
      id: job.id,
      changed: [ "workflows", "runs", "state" ]
    )
  end
end
