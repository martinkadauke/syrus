class ProviderSessionPruneJob < ApplicationJob
  include SkipIfPending

  queue_as :cleanup

  # Daily housekeeping. Delete rows for terminal Runs older than
  # RETAIN_AFTER_TERMINAL. Active Runs are never touched.
  #
  # We intentionally keep transcripts for recent succeeded workflow Runs:
  # downstream short agentic steps may need to rehydrate provider resume state
  # after worker movement or deploys.
  def perform
    n_deleted = ProviderSession.prunable.delete_all
    Rails.logger.info("[ProviderSessionPrune] deleted #{n_deleted} sessions") if n_deleted > 0
  end
end
