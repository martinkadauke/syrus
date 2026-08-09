class AddChatBookmarkPayloadIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :chat_bookmarks,
              [ :chat_message_id, :id ],
              name: "idx_chat_bookmarks_message_id_id",
              if_not_exists: true
  end
end
