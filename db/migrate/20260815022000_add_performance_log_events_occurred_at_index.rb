class AddPerformanceLogEventsOccurredAtIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :performance_log_events,
      :occurred_at,
      name: "idx_perf_events_occurred_at",
      if_not_exists: true
  end
end
