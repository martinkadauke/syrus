class AddFailedExecutionCreatedAtIndex < ActiveRecord::Migration[8.1]
  def change
    return unless table_exists?(:solid_queue_failed_executions)
    return if index_exists?(:solid_queue_failed_executions, [ :created_at, :job_id ], name: "index_solid_queue_failed_executions_on_created_at_job_id")

    add_index :solid_queue_failed_executions,
      [ :created_at, :job_id ],
      name: "index_solid_queue_failed_executions_on_created_at_job_id"
  end
end
