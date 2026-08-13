class AddChatAttachmentPayloadIndex < ActiveRecord::Migration[8.1]
  def change
    columns = [ :chat_session_id, :attachable_type, :attached_at, :id ]

    unless index_exists?(:chat_attachments, columns, name: "idx_chat_attachments_payload_order")
      add_index :chat_attachments,
                columns,
                name: "idx_chat_attachments_payload_order"
    end
  end
end
