# Proposal-outcome agent notification extracted from ChatsController: posts a
# system message telling the agent a proposal was confirmed/rejected and
# builds its control-content payload. Kept private on include.
module ChatProposalOutcomeNotice
  private

  def notify_agent_of_proposal_outcome(message)
    chat_session = message.chat_session
    return unless chat_session

    ApplicationRecord.transaction do
      chat_session.update!(
        last_message_at: Time.current,
        title: chat_session.title.presence
      )
    end

    enqueue_chat_turn(chat_session, message)
  end

  def proposal_outcome_control_content(proposal, text:, outcome:)
    {
      "text" => text,
      "source" => ChatProposalOutcomeNotification::SOURCE,
      "outcome" => outcome.to_s,
      "acknowledgment" => ChatProposalOutcomeNotification.acknowledgment(proposal, outcome: outcome)
    }
  end
end
