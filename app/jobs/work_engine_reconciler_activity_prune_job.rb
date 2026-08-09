class WorkEngineReconcilerActivityPruneJob < ApplicationJob
  include SkipIfPending

  queue_as :cleanup

  def perform
    deleted = WorkEngineReconcilerActivityEvent.prunable.delete_all
    Rails.logger.info("[WorkEngineReconcilerActivityPruneJob] deleted #{deleted} reconciler activity events") if deleted > 0
  end
end
