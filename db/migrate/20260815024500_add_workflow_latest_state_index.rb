class AddWorkflowLatestStateIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :workflows,
      [ :job_id, :state, :finished_at, :id ],
      name: "idx_workflows_job_state_finished_latest",
      if_not_exists: true
  end
end
