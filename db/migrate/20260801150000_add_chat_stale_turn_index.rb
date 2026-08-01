class AddChatStaleTurnIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :chat_sessions, [ :turn_in_flight, :last_message_at ], name: "idx_chat_sessions_stale_turns"
  end
end
