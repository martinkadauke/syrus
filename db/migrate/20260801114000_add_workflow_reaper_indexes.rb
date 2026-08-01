class AddWorkflowReaperIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :workflows,
              [ :state, :started_at, :id ],
              name: "idx_workflows_state_started_at",
              if_not_exists: true
    add_index :workflows,
              [ :state, :created_at, :id ],
              name: "idx_workflows_state_created_at",
              if_not_exists: true
  end
end
