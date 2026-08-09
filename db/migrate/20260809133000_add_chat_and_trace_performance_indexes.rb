class AddChatAndTracePerformanceIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :chat_messages,
              [ :chat_session_id, :role, :tool_name, :created_at, :id ],
              name: "idx_chat_messages_session_role_tool_created_id",
              if_not_exists: true

    add_index :notifications,
              [ :user_id, :read_at ],
              name: "idx_notifications_user_read_at",
              if_not_exists: true

    add_index :spawned_processes,
              [ :started_at, :hostname ],
              name: "idx_spawned_processes_started_hostname",
              if_not_exists: true
  end
end
