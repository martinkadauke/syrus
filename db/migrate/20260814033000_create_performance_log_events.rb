class CreatePerformanceLogEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :performance_log_events do |t|
      t.datetime :occurred_at, null: false
      t.string :app_revision
      t.string :event_name, null: false
      t.string :request_id
      t.string :method, limit: 20
      t.string :path, limit: 500
      t.string :controller, limit: 200
      t.string :action, limit: 100
      t.string :phase, limit: 200
      t.string :name, limit: 200
      t.string :trace_id, limit: 100
      t.string :sql_fingerprint, limit: 700
      t.float :duration_ms
      t.integer :sql_count
      t.float :sql_duration_ms
      t.integer :slow_sql_count
      t.json :payload, null: false

      t.timestamps
    end

    unless index_exists?(:performance_log_events, [ :app_revision, :occurred_at ], name: "idx_perf_events_revision_occurred")
      add_index :performance_log_events, [ :app_revision, :occurred_at ], name: "idx_perf_events_revision_occurred"
    end
    unless index_exists?(:performance_log_events, [ :event_name, :occurred_at ], name: "idx_perf_events_name_occurred")
      add_index :performance_log_events, [ :event_name, :occurred_at ], name: "idx_perf_events_name_occurred"
    end
    unless index_exists?(:performance_log_events, [ :path, :occurred_at ], name: "idx_perf_events_path_occurred")
      add_index :performance_log_events, [ :path, :occurred_at ], name: "idx_perf_events_path_occurred"
    end
    unless index_exists?(:performance_log_events, [ :phase, :occurred_at ], name: "idx_perf_events_phase_occurred")
      add_index :performance_log_events, [ :phase, :occurred_at ], name: "idx_perf_events_phase_occurred"
    end
    unless index_exists?(:performance_log_events, [ :sql_fingerprint, :occurred_at ], name: "idx_perf_events_sql_fingerprint_occurred")
      add_index :performance_log_events, [ :sql_fingerprint, :occurred_at ], name: "idx_perf_events_sql_fingerprint_occurred"
    end
  end
end
