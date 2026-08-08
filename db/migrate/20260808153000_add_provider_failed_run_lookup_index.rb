class AddProviderFailedRunLookupIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :runs,
      [ :state, :agent_provider, :finished_at, :updated_at, :id ],
      name: "idx_runs_provider_failed_recent",
      if_not_exists: true
  end
end
