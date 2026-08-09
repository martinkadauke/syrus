class CreateWorkEngineReconcilerActivityEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :work_engine_reconciler_activity_events do |t|
      t.string :event_type, null: false
      t.string :source, null: false
      t.string :severity, null: false, default: "info"
      t.references :job, foreign_key: true
      t.references :workflow, foreign_key: true
      t.references :step, foreign_key: true
      t.references :run, foreign_key: true
      t.string :issue_kind
      t.string :repair_action
      t.string :repair_status
      t.text :message, null: false
      t.json :details, null: false
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :work_engine_reconciler_activity_events, :occurred_at
    add_index :work_engine_reconciler_activity_events, [ :source, :occurred_at ], name: "index_reconciler_activity_on_source_and_occurred_at"
    add_index :work_engine_reconciler_activity_events, [ :event_type, :occurred_at ], name: "index_reconciler_activity_on_type_and_occurred_at"
    add_index :work_engine_reconciler_activity_events, [ :job_id, :occurred_at ], name: "index_reconciler_activity_on_job_and_occurred_at"
    add_index :work_engine_reconciler_activity_events, [ :workflow_id, :occurred_at ], name: "index_reconciler_activity_on_workflow_and_occurred_at"
    add_index :work_engine_reconciler_activity_events, [ :run_id, :occurred_at ], name: "index_reconciler_activity_on_run_and_occurred_at"
  end
end
