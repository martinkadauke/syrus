class StepDispatcher
  # When a Step transitions to `succeeded`, advance the Workflow:
  # find the next Step in the chain, create a Run on it, enqueue
  # the runner. If there is no next step, the Workflow itself
  # transitions to succeeded.
  #
  # v1 stub: full implementation lands together with StepRunJob in
  # the dispatcher commit. Today this method exists so that
  # Step#after_update_commit doesn't NoMethodError; a Step that
  # transitions to `succeeded` before the dispatcher is wired just
  # leaves the Workflow without auto-advancing — fine because
  # nothing creates Steps via the new path yet.
  def self.advance_from(step)
    Rails.logger.debug("[StepDispatcher] advance_from step ##{step.id} (#{step.kind}) — stub, no-op until full dispatcher lands")
  end
end
