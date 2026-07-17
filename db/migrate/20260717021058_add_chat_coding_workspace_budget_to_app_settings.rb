class AddChatCodingWorkspaceBudgetToAppSettings < ActiveRecord::Migration[8.1]
  def up
    unless column_exists?(:app_settings, :chat_coding_workspace_budget_mb)
      add_column :app_settings, :chat_coding_workspace_budget_mb, :integer, default: 0, null: false
    end
  end

  def down
    if column_exists?(:app_settings, :chat_coding_workspace_budget_mb)
      remove_column :app_settings, :chat_coding_workspace_budget_mb
    end
  end
end
