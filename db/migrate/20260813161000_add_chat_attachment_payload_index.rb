class AddChatAttachmentPayloadIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :chat_attachments,
              [ :chat_session_id, :attachable_type, :attached_at, :id ],
              name: "idx_chat_attachments_payload_order"
  end
end
