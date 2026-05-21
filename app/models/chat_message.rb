class ChatMessage < ApplicationRecord
  ROLES = %w[ user assistant tool_use tool_result system ].freeze

  belongs_to :chat_session
  belongs_to :proposal, class_name: "ChatProposal", optional: true

  has_many :bookmarks, class_name: "ChatBookmark", dependent: :destroy, inverse_of: :chat_message

  after_create_commit :broadcast_to_chat
  after_create_commit :broadcast_controls_update

  validates :role, presence: true, inclusion: { in: ROLES }
  validate :content_is_present

  # Proposal-bearing rows render as inline proposal cards. All other
  # tool_use messages flow through ChatMessageGrouper and the
  # tool_call_group partial — collapsed by default, no per-message
  # expansion logic needed.
  def proposal_tool_use?
    role == "tool_use" && proposal_id.present?
  end

  def proposal_card?
    role == "assistant" && proposal_id.present?
  end

  def bookmarkable?
    role.in?(%w[user assistant])
  end

  private

  def content_is_present
    errors.add(:content, "can't be blank") if content.nil?
  end

  def broadcast_to_chat
    # Sync broadcast (NOT _later_to): a single agent turn produces
    # 30–80 ChatMessages (one per tool_call / tool_result /
    # assistant_text chunk). Routing each broadcast through
    # ActiveJob piles them into the `default` queue behind the
    # polling/reaper jobs, which makes the chat window stop
    # updating mid-turn until the queue drains. Inline via
    # solid_cable is fast and keeps the operator's UI honest.
    broadcast_append_to(
      "chat_session_#{chat_session_id}_messages",
      target: "chat_session_#{chat_session_id}_messages",
      partial: "chats/message",
      locals: { message: self, repository: chat_session.repository }
    )
  end

  # Any new message can flip `turn_in_flight?`: a user message starts a
  # turn, a non-user message ends it. Re-render the compose partial so
  # its disabled state matches.
  def broadcast_controls_update
    chat_session.broadcast_controls
  end
end
