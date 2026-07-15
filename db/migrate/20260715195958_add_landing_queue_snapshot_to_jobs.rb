class AddLandingQueueSnapshotToJobs < ActiveRecord::Migration[8.1]
  def up
    add_column :jobs, :landing_queue_position, :integer unless column_exists?(:jobs, :landing_queue_position)
    add_column :jobs, :landing_queue_blocked_reason, :string unless column_exists?(:jobs, :landing_queue_blocked_reason)
    add_column :jobs, :landing_queue_entry_key, :string unless column_exists?(:jobs, :landing_queue_entry_key)
    add_column :jobs, :landing_queue_blocker_job_ids, :json unless column_exists?(:jobs, :landing_queue_blocker_job_ids)
    add_column :jobs, :landing_queue_waiting_job_ids, :json unless column_exists?(:jobs, :landing_queue_waiting_job_ids)
    add_column :jobs, :landing_queue_dependency_edges, :json unless column_exists?(:jobs, :landing_queue_dependency_edges)
    add_column :jobs, :landing_queue_cached_at, :datetime unless column_exists?(:jobs, :landing_queue_cached_at)

    add_index :jobs, [ :state, :landing_queue_position, :id ] unless index_exists?(:jobs, [ :state, :landing_queue_position, :id ])
    add_index :jobs, :landing_queue_entry_key unless index_exists?(:jobs, :landing_queue_entry_key)
  end

  def down
    remove_index :jobs, :landing_queue_entry_key if index_exists?(:jobs, :landing_queue_entry_key)
    remove_index :jobs, [ :state, :landing_queue_position, :id ] if index_exists?(:jobs, [ :state, :landing_queue_position, :id ])

    remove_column :jobs, :landing_queue_cached_at if column_exists?(:jobs, :landing_queue_cached_at)
    remove_column :jobs, :landing_queue_dependency_edges if column_exists?(:jobs, :landing_queue_dependency_edges)
    remove_column :jobs, :landing_queue_waiting_job_ids if column_exists?(:jobs, :landing_queue_waiting_job_ids)
    remove_column :jobs, :landing_queue_blocker_job_ids if column_exists?(:jobs, :landing_queue_blocker_job_ids)
    remove_column :jobs, :landing_queue_entry_key if column_exists?(:jobs, :landing_queue_entry_key)
    remove_column :jobs, :landing_queue_blocked_reason if column_exists?(:jobs, :landing_queue_blocked_reason)
    remove_column :jobs, :landing_queue_position if column_exists?(:jobs, :landing_queue_position)
  end
end
