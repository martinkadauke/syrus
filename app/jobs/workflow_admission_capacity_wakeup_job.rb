class WorkflowAdmissionCapacityWakeupJob < ApplicationJob
  include SkipIfPending

  queue_as :control_plane

  def perform
    WorkflowAdmissionCapacityWakeup.call
  end
end
