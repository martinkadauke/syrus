class AddLandingQueueEntryPositionToJobs < ActiveRecord::Migration[8.1]
  def up
    add_column :jobs, :landing_queue_entry_position, :integer unless column_exists?(:jobs, :landing_queue_entry_position)
    add_index :jobs, [ :state, :landing_queue_entry_position, :id ] unless index_exists?(:jobs, [ :state, :landing_queue_entry_position, :id ])
  end

  def down
    remove_index :jobs, [ :state, :landing_queue_entry_position, :id ] if index_exists?(:jobs, [ :state, :landing_queue_entry_position, :id ])
    remove_column :jobs, :landing_queue_entry_position if column_exists?(:jobs, :landing_queue_entry_position)
  end
end
