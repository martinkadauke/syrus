class AddOnboardingToChatSessions < ActiveRecord::Migration[8.1]
  def up
    add_column :chat_sessions, :onboarding, :boolean, default: false, null: false unless column_exists?(:chat_sessions, :onboarding)
  end

  def down
    remove_column :chat_sessions, :onboarding if column_exists?(:chat_sessions, :onboarding)
  end
end
