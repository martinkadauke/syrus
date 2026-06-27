class AddChatMessagesSessionIdCursorIndex < ActiveRecord::Migration[8.1]
  def up
    add_index :chat_messages, [ :chat_session_id, :id ], name: "index_chat_messages_on_session_id_and_id" unless index_exists?(:chat_messages, [ :chat_session_id, :id ], name: "index_chat_messages_on_session_id_and_id")
  end

  def down
    remove_index :chat_messages, name: "index_chat_messages_on_session_id_and_id" if index_exists?(:chat_messages, name: "index_chat_messages_on_session_id_and_id")
  end
end
