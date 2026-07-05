class AddSenderUserIdToChatMessages < ActiveRecord::Migration[8.1]
  def up
    unless column_exists?(:chat_messages, :sender_user_id)
      add_column :chat_messages, :sender_user_id, :bigint
      add_index :chat_messages, :sender_user_id unless index_exists?(:chat_messages, :sender_user_id)
      add_foreign_key :chat_messages, :users, column: :sender_user_id unless
        foreign_key_exists?(:chat_messages, column: :sender_user_id)
    end

    # Backfill sender_user_id from the session owner for existing user-role messages.
    execute <<~SQL
      UPDATE chat_messages
      SET sender_user_id = (
        SELECT user_id FROM chat_sessions
        WHERE chat_sessions.id = chat_messages.chat_session_id
      )
      WHERE role = 'user'
        AND sender_user_id IS NULL
    SQL
  end

  def down
    if foreign_key_exists?(:chat_messages, column: :sender_user_id)
      remove_foreign_key :chat_messages, column: :sender_user_id
    end
    remove_column :chat_messages, :sender_user_id if column_exists?(:chat_messages, :sender_user_id)
  end
end
