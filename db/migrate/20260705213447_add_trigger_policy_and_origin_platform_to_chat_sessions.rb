class AddTriggerPolicyAndOriginPlatformToChatSessions < ActiveRecord::Migration[8.1]
  def up
    unless column_exists?(:chat_sessions, :trigger_policy)
      add_column :chat_sessions, :trigger_policy, :string, null: false, default: "speak_when_spoken_to"
    end

    unless column_exists?(:chat_sessions, :origin_platform)
      add_column :chat_sessions, :origin_platform, :string
    end

    unless index_exists?(:chat_sessions, [ :origin_platform, :user_id ])
      add_index :chat_sessions, [ :origin_platform, :user_id ]
    end
  end

  def down
    if index_exists?(:chat_sessions, [ :origin_platform, :user_id ])
      remove_index :chat_sessions, [ :origin_platform, :user_id ]
    end
    remove_column :chat_sessions, :origin_platform if column_exists?(:chat_sessions, :origin_platform)
    remove_column :chat_sessions, :trigger_policy if column_exists?(:chat_sessions, :trigger_policy)
  end
end
