class AddManualPauseToJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :jobs, :manual_paused, :boolean, null: false, default: false
    add_column :jobs, :manual_paused_at, :datetime
    add_reference :jobs, :manual_paused_by_user, foreign_key: { to_table: :users }, index: true

    add_index :jobs, [ :manual_paused, :state, :id ], name: "index_jobs_on_manual_paused_state_id"
  end
end
