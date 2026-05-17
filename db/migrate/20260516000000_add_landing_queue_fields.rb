class AddLandingQueueFields < ActiveRecord::Migration[8.1]
  # `approved_at` is already added by AddApprovalStateToJobs
  # (20260516002034), so it's intentionally omitted here. Remaining
  # adds + indexes are guarded with existence checks per CLAUDE.md
  # so partial state from a crashed earlier deploy attempt doesn't
  # crash the retry with `Duplicate column name`.
  def up
    add_column :jobs, :landing_failure_reason, :text unless column_exists?(:jobs, :landing_failure_reason)
    add_column :users, :landing_paused, :boolean, default: false, null: false unless column_exists?(:users, :landing_paused)

    add_index :jobs, [ :state, :approved_at, :id ] unless index_exists?(:jobs, [ :state, :approved_at, :id ])
    add_index :users, :landing_paused unless index_exists?(:users, :landing_paused)
  end

  def down
    remove_index :jobs, [ :state, :approved_at, :id ] if index_exists?(:jobs, [ :state, :approved_at, :id ])
    remove_index :users, :landing_paused if index_exists?(:users, :landing_paused)
    remove_column :users, :landing_paused if column_exists?(:users, :landing_paused)
    remove_column :jobs, :landing_failure_reason if column_exists?(:jobs, :landing_failure_reason)
  end
end
