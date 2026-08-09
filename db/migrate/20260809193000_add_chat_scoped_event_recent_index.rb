class AddChatScopedEventRecentIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :chat_scoped_events,
      [ :chat_session_id, :created_at, :id ],
      name: "idx_chat_scoped_events_session_created_id",
      if_not_exists: true
  end
end
