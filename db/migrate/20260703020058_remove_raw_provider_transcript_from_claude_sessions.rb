class RemoveRawProviderTranscriptFromClaudeSessions < ActiveRecord::Migration[8.1]
  def up
    remove_column :claude_sessions, :raw_provider_transcript if column_exists?(:claude_sessions, :raw_provider_transcript)
  end

  def down
    add_column :claude_sessions, :raw_provider_transcript, :text unless column_exists?(:claude_sessions, :raw_provider_transcript)
  end
end
