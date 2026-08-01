class AddMorePerformanceHotPathIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :jobs,
      [ :user_id, :state, :closure_reason, :finished_at ],
      name: "idx_jobs_user_state_closure_finished",
      if_not_exists: true

    add_index :jobs,
      [ :repository_id, :state, :closure_reason, :finished_at ],
      name: "idx_jobs_repo_state_closure_finished",
      if_not_exists: true

    add_index :jobs,
      [ :repository_id, :updated_at, :id ],
      name: "idx_jobs_repo_updated_latest",
      if_not_exists: true

    add_index :runs,
      [ :state, :job_id, :updated_at ],
      name: "idx_runs_state_job_updated",
      if_not_exists: true

    add_index :spawned_processes,
      [ :finished_at, :hostname, :pid, :last_chunk_at ],
      name: "idx_spawned_processes_active_host_pid",
      if_not_exists: true
  end
end
