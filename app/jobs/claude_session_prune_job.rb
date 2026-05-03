class ClaudeSessionPruneJob < ApplicationJob
  queue_as :default

  # Daily housekeeping. Sessions for terminal Runs older than
  # ClaudeSession::RETAIN_AFTER_TERMINAL get deleted. Active Runs are
  # never touched.
  def perform
    n = ClaudeSession.prunable.delete_all
    Rails.logger.info("[ClaudeSessionPrune] deleted #{n} sessions") if n > 0
  end
end
