class AddForkAutoSyncEnabledToRepositories < ActiveRecord::Migration[8.1]
  def up
    unless column_exists?(:repositories, :fork_auto_sync_enabled)
      add_column :repositories, :fork_auto_sync_enabled, :boolean, default: false, null: false
    end
  end

  def down
    if column_exists?(:repositories, :fork_auto_sync_enabled)
      remove_column :repositories, :fork_auto_sync_enabled
    end
  end
end
