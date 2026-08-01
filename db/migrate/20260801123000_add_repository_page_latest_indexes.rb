class AddRepositoryPageLatestIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :runs, [ :job_id, :created_at, :id ], name: "idx_runs_job_latest", if_not_exists: true
    add_index :workflows, [ :job_id, :finished_at, :id ], name: "idx_workflows_job_finished_latest", if_not_exists: true
  end
end
