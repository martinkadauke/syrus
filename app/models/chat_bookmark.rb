class ChatBookmark < ApplicationRecord
  KINDS = %w[ topic epic_origin manual ].freeze

  belongs_to :chat_message, inverse_of: :bookmarks

  after_create_commit :broadcast_app_event

  enum :kind, {
    topic: "topic",
    epic_origin: "epic_origin",
    manual: "manual"
  }, validate: true

  validates :label, :kind, presence: true
  validates :kind, inclusion: { in: KINDS }

  def anchor_message_id
    message = chat_message
    return message.id if message.bookmarkable?

    session = message.chat_session
    renderable_message_scope(session)
      .where(role: %w[user assistant])
      .where("id > ?", message.id)
      .order(:id)
      .pick(:id) ||
      renderable_message_scope(session)
        .where(role: %w[user assistant])
        .where("id < ?", message.id)
        .order(id: :desc)
        .pick(:id) ||
      message.id
  end

  private

  def renderable_message_scope(session)
    scope = session.messages
    return scope unless ActiveRecord::Base.connection.adapter_name.downcase.include?("mysql")

    scope.from(Arel.sql("#{ChatMessage.quoted_table_name} FORCE INDEX (index_chat_messages_on_session_id_and_id)"))
  end

  def broadcast_app_event
    chat = chat_message.chat_session
    AppEvents.broadcast(
      user: chat.user,
      type: "updated",
      resource: "chat",
      id: chat.id,
      changed: [ "bookmarks" ],
      payload: {
        action: "upsert_bookmark",
        bookmark: {
          id: id,
          label: label,
          chat_message_id: chat_message_id,
          anchor_message_id: anchor_message_id
        }
      }
    )
  end
end
