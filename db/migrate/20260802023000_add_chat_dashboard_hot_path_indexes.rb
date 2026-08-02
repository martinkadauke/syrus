class AddChatDashboardHotPathIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :spawned_processes,
      [ :kind, :workdir, :finished_at ],
      name: "idx_spawned_processes_kind_workdir_active",
      length: { workdir: 512 },
      if_not_exists: true

    add_index :chat_messages,
      [ :chat_session_id, :created_at, :id ],
      name: "idx_chat_messages_session_created_id",
      if_not_exists: true
  end
end
