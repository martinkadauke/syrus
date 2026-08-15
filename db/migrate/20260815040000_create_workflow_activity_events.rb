class CreateWorkflowActivityEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :workflow_activity_events do |t|
      t.datetime :occurred_at, null: false
      t.string :event_type, null: false
      t.string :source, null: false
      t.string :severity, null: false, default: "info"
      t.string :app_revision
      t.string :hostname
      t.integer :pid
      t.references :repository, foreign_key: true
      t.references :epic, foreign_key: true
      t.references :job, foreign_key: true
      t.references :workflow, foreign_key: true
      t.references :step, foreign_key: true
      t.references :run, foreign_key: true
      t.string :trigger_kind
      t.string :workflow_state
      t.string :step_kind
      t.string :run_state
      t.string :reason_key
      t.float :duration_ms
      t.text :message, null: false
      t.json :metadata, null: false

      t.timestamps
    end

    add_index :workflow_activity_events, :occurred_at
    add_index :workflow_activity_events, [ :job_id, :occurred_at ], name: "idx_workflow_activity_job_occurred"
    add_index :workflow_activity_events, [ :workflow_id, :occurred_at ], name: "idx_workflow_activity_workflow_occurred"
    add_index :workflow_activity_events, [ :run_id, :occurred_at ], name: "idx_workflow_activity_run_occurred"
    add_index :workflow_activity_events, [ :repository_id, :occurred_at ], name: "idx_workflow_activity_repo_occurred"
    add_index :workflow_activity_events, [ :event_type, :occurred_at ], name: "idx_workflow_activity_type_occurred"
    add_index :workflow_activity_events, [ :trigger_kind, :occurred_at ], name: "idx_workflow_activity_trigger_occurred"
    add_index :workflow_activity_events, [ :reason_key, :occurred_at ], name: "idx_workflow_activity_reason_occurred"
  end
end
