class AddPerfIndexesForChatAndAutoRetries < ActiveRecord::Migration[8.1]
  def up
    add_index :chat_messages,
              [ :chat_session_id, :role ],
              name: "idx_chat_messages_session_role",
              if_not_exists: true

    add_index :auto_retry_attempts,
              [ :job_id, :agent_provider, :failure_classification, :skipped_reason ],
              name: "idx_auto_retry_attempts_budget_skipped",
              if_not_exists: true

    add_index :auto_retry_attempts,
              [ :workflow_id, :performed_at, :skipped_reason ],
              name: "idx_auto_retry_attempts_workflow_pending",
              if_not_exists: true
  end

  def down
    remove_index :auto_retry_attempts, name: "idx_auto_retry_attempts_workflow_pending", if_exists: true
    remove_index :auto_retry_attempts, name: "idx_auto_retry_attempts_budget_skipped", if_exists: true
    remove_index :chat_messages, name: "idx_chat_messages_session_role", if_exists: true
  end
end
