class AddRepositoryThroughputMetricIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :steps,
      [ :kind, :state, :finished_at, :workflow_id ],
      name: "idx_steps_throughput_kind_state_finished",
      if_not_exists: true

    add_index :runs,
      [ :state, :finished_at, :step_id ],
      name: "idx_runs_throughput_state_finished",
      if_not_exists: true

    add_index :workflows,
      [ :trigger_kind, :state, :started_at, :job_id ],
      name: "idx_workflows_throughput_trigger_state_started",
      if_not_exists: true

    add_index :workflows,
      [ :trigger_kind, :finished_at, :job_id ],
      name: "idx_workflows_throughput_trigger_finished",
      if_not_exists: true
  end
end
