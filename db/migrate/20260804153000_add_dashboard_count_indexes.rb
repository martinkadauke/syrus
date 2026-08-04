class AddDashboardCountIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :jobs,
      [ :repository_id, :owner_user_id, :kind, :state ],
      name: "idx_jobs_dashboard_repo_owner_kind_state",
      if_not_exists: true

    add_index :jobs,
      [ :repository_id, :user_id, :kind, :state ],
      name: "idx_jobs_dashboard_repo_user_kind_state",
      if_not_exists: true

    add_index :workflows,
      [ :job_id, :state ],
      name: "idx_workflows_job_state",
      if_not_exists: true
  end
end
