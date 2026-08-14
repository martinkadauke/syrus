class AddChatAttachmentRepositoryGroupIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :chat_attachments,
              [ :attachable_type, :attachable_id, :chat_session_id ],
              name: "idx_chat_attachments_attachable_session",
              if_not_exists: true
  end
end
