class AddChatScopedEventRecentIndex < ActiveRecord::Migration[8.1]
  def change
    unless index_exists?(:chat_scoped_events, [ :chat_session_id, :created_at, :id ], name: "idx_chat_scoped_events_session_created_id")
      add_index :chat_scoped_events,
        [ :chat_session_id, :created_at, :id ],
        name: "idx_chat_scoped_events_session_created_id"
    end
  end
end
