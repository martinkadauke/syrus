class RenameClaudeSessionsToProviderSessions < ActiveRecord::Migration[8.1]
  INDEX_RENAMES = {
    "index_claude_sessions_on_created_at" => "index_provider_sessions_on_created_at",
    "index_claude_sessions_on_resumable" => "index_provider_sessions_on_resumable",
    "index_claude_sessions_on_run_id" => "index_provider_sessions_on_run_id"
  }.freeze

  def up
    rename_table :claude_sessions, :provider_sessions if table_exists?(:claude_sessions) && !table_exists?(:provider_sessions)
    rename_indexes(INDEX_RENAMES)
  end

  def down
    rename_indexes(INDEX_RENAMES.invert)
    rename_table :provider_sessions, :claude_sessions if table_exists?(:provider_sessions) && !table_exists?(:claude_sessions)
  end

  private

  def rename_indexes(mapping)
    mapping.each do |old_name, new_name|
      next unless index_name_exists?(:provider_sessions, old_name)
      next if index_name_exists?(:provider_sessions, new_name)

      rename_index :provider_sessions, old_name, new_name
    end
  end
end
