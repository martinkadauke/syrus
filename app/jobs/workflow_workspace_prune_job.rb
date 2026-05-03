class WorkflowWorkspacePruneJob < ApplicationJob
  queue_as :default

  # How long to keep a terminal Workflow's workspace on disk before
  # the daily prune sweeps it. Failed workflows benefit from the
  # retention because the operator can hit "Retry from failed step"
  # and pick up the prior succeeded steps' state. Succeeded /
  # cancelled workflows usually have their workspace cleaned up by
  # the AASM terminal-transition callback already; this job is a
  # backstop for the rare case where that cleanup didn't happen
  # (worker died between succeed and cleanup_workspace!, etc.).
  RETAIN_AFTER_TERMINAL = 7.days

  def perform
    cutoff = RETAIN_AFTER_TERMINAL.ago
    candidates = Workflow.where(state: %w[ succeeded failed cancelled ])
                         .where(cleaned_up_at: nil)
                         .where("finished_at IS NOT NULL AND finished_at < ?", cutoff)
    n = 0
    candidates.find_each do |wf|
      WorkflowWorkspace.cleanup_for(wf)
      n += 1
    end
    Rails.logger.info("[WorkflowWorkspacePrune] cleaned #{n} workflow workspaces past retention") if n > 0
  end
end
