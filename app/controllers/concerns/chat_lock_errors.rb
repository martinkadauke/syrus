# Transient chat-lock error handling extracted from ChatsController: renders
# the retry-after response for a temporary per-Job lock and inspects an error
# chain to detect the transient lock case. Kept private on include.
module ChatLockErrors
  private

  def render_temporary_chat_lock_error
    render_error(
      "temporary_lock",
      "Chat request was blocked by a temporary database lock. Try again.",
      status: :service_unavailable
    )
  end

  def transient_chat_lock_error?(error)
    error_chain(error).any? do |candidate|
      candidate.is_a?(ActiveRecord::LockWaitTimeout) ||
        candidate.is_a?(ActiveRecord::Deadlocked) ||
        candidate.is_a?(ActiveRecord::StatementTimeout) ||
        candidate.class.name == "SQLite3::BusyException" ||
        candidate.message.match?(/SQLite3::BusyException|database is locked|LockWaitTimeout|Deadlocked|StatementTimeout/i)
    end
  end

  def error_chain(error)
    chain = []
    while error && !chain.include?(error)
      chain << error
      error = error.cause
    end
    chain
  end
end
