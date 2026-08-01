class AddProviderLatestIndexToRuns < ActiveRecord::Migration[8.1]
  def change
    add_index :runs,
              [ :user_id, :agent_provider, :finished_at, :updated_at, :id ],
              name: "idx_runs_provider_latest_finished",
              if_not_exists: true
  end
end
