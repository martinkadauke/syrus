class AddSpawnedProcessAdminIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :spawned_processes,
              [ :finished_at, :kind ],
              name: "idx_spawned_processes_active_kind",
              if_not_exists: true
  end
end
