class CreateChatContextCheckpoints < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_context_checkpoints do |t|
      t.references :chat_session, null: false, foreign_key: true
      t.bigint :compacted_through_message_id, null: false
      t.integer :source_message_count, null: false
      t.integer :summary_version, null: false, default: 1
      t.text :summary, null: false
      t.timestamps

      t.index [ :chat_session_id, :compacted_through_message_id ],
              unique: true,
              name: "idx_chat_context_checkpoints_session_message"
      t.index [ :chat_session_id, :created_at ],
              name: "idx_chat_context_checkpoints_session_created"
    end
  end
end
