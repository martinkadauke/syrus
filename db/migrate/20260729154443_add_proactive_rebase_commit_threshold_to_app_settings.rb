class AddProactiveRebaseCommitThresholdToAppSettings < ActiveRecord::Migration[8.1]
  def up
    add_column :app_settings, :proactive_rebase_commit_threshold, :integer, default: 20, null: false unless column_exists?(:app_settings, :proactive_rebase_commit_threshold)
  end

  def down
    remove_column :app_settings, :proactive_rebase_commit_threshold if column_exists?(:app_settings, :proactive_rebase_commit_threshold)
  end
end
