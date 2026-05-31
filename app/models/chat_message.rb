class ChatMessage < ApplicationRecord
  ROLES = %w[ user assistant tool_use tool_result system ].freeze
  SPA_EVENT_TAIL_SIZE = 24

  belongs_to :chat_session
  belongs_to :proposal, class_name: "ChatProposal", optional: true

  has_many :bookmarks, class_name: "ChatBookmark", dependent: :destroy, inverse_of: :chat_message

  after_create_commit :broadcast_to_chat
  after_create_commit :broadcast_controls_update
  after_create_commit :broadcast_app_event

  validates :role, presence: true, inclusion: { in: ROLES }
  validate :content_is_present

  # Proposal-bearing rows render as inline proposal cards in the
  # legacy ERB fallback. All other tool_use messages flow through
  # ChatMessageGrouper there; the React chat receives raw message
  # records and does its own grouping client-side.
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
    chat_session.broadcast_controls(app_event: false)
  end

  def broadcast_app_event
    chat = chat_session
    tail = chat.messages
               .includes(proposal: [ :repository, :job, :epic, :target_epic, dependencies: [], child_proposals: [ :repository, dependencies: [] ] ])
               .order(created_at: :desc, id: :desc)
               .limit(SPA_EVENT_TAIL_SIZE)
               .to_a
               .reverse

    AppEvents.broadcast(
      user: chat.user,
      type: "updated",
      resource: "chat",
      id: chat_session_id,
      changed: [ "messages" ],
      payload: {
        action: "replace_tail",
        replace_from_id: tail.first&.id,
        messages: ::App::ChatMessagePayload.messages(tail, repository: chat.repository),
        turn_in_flight: chat.turn_in_flight?,
        stop_requested_at: chat.stop_requested_at&.iso8601
      }
    )
  end
end
