class CreateChatScopedEvents < ActiveRecord::Migration[8.1]
  def change
    unless table_exists?(:chat_scoped_events)
      create_table :chat_scoped_events do |t|
        t.references :chat_session, null: false
        t.references :repository
        t.references :job
        t.references :epic
        t.references :proposal
        t.references :chat_message
        t.string :source_kind, null: false
        t.string :delivery_state, null: false, default: "pending"
        t.string :dedupe_key
        t.json :payload, null: false
        t.datetime :delivered_at

        t.timestamps
      end
    end

    add_foreign_key :chat_scoped_events, :chat_sessions unless foreign_key_exists?(:chat_scoped_events, :chat_sessions)
    add_foreign_key :chat_scoped_events, :repositories unless foreign_key_exists?(:chat_scoped_events, :repositories)
    add_foreign_key :chat_scoped_events, :jobs unless foreign_key_exists?(:chat_scoped_events, :jobs)
    add_foreign_key :chat_scoped_events, :epics unless foreign_key_exists?(:chat_scoped_events, :epics)
    add_foreign_key :chat_scoped_events, :chat_proposals, column: :proposal_id unless foreign_key_exists?(:chat_scoped_events, :chat_proposals, column: :proposal_id)
    add_foreign_key :chat_scoped_events, :chat_messages unless foreign_key_exists?(:chat_scoped_events, :chat_messages)

    unless index_exists?(:chat_scoped_events, [ :chat_session_id, :delivery_state, :created_at ], name: "idx_chat_scoped_events_delivery")
      add_index :chat_scoped_events, [ :chat_session_id, :delivery_state, :created_at ], name: "idx_chat_scoped_events_delivery"
    end

    unless index_exists?(:chat_scoped_events, [ :chat_session_id, :dedupe_key ], name: "idx_chat_scoped_events_dedupe")
      add_index :chat_scoped_events, [ :chat_session_id, :dedupe_key ], unique: true, name: "idx_chat_scoped_events_dedupe"
    end
  end
end
