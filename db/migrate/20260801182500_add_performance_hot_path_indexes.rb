class AddPerformanceHotPathIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :coverage_snapshots,
      [ :repository_id, :branch, :created_at ],
      name: "idx_coverage_snapshots_repo_branch_created",
      if_not_exists: true

    add_index :runs,
      [ :step_id, :created_at, :id ],
      name: "idx_runs_step_created",
      if_not_exists: true

    add_index :spawned_processes,
      [ :run_id, :finished_at, :started_at, :id ],
      name: "idx_spawned_processes_run_active_started",
      if_not_exists: true

    add_index :run_health_snapshots,
      [ :run_id, :created_at, :id ],
      name: "idx_run_health_snapshots_run_created",
      if_not_exists: true
  end
end
