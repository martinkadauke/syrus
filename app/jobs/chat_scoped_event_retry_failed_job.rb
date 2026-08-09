class ChatScopedEventRetryFailedJob < ApplicationJob
  queue_as :low_priority_maintenance

  WINDOW = 24.hours
  MAX_EVENTS = 50

  def perform
    ChatScopedEvent
      .pending
      .where(evaluator_state: "failed")
      .where("created_at >= ?", WINDOW.ago)
      .order(:evaluated_at, :id)
      .limit(MAX_EVENTS)
      .find_each do |event|
        next unless event.retry_evaluator!

        ChatScopedEventEvaluatorJob.perform_later(event.id, event.chat_session_id)
      end
  end
end
