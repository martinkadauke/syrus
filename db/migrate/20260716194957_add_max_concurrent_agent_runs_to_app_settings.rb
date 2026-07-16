class AddMaxConcurrentAgentRunsToAppSettings < ActiveRecord::Migration[8.1]
  def up
    unless column_exists?(:app_settings, :max_concurrent_agent_runs)
      add_column :app_settings, :max_concurrent_agent_runs, :integer, default: 0, null: false
    end
  end

  def down
    if column_exists?(:app_settings, :max_concurrent_agent_runs)
      remove_column :app_settings, :max_concurrent_agent_runs
    end
  end
end
