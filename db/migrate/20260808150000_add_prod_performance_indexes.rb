class AddProdPerformanceIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :job_logs,
      [ :kind, :run_id ],
      name: "idx_job_logs_kind_run_id",
      if_not_exists: true

    add_index :merge_train_members,
      [ :job_id, :merge_train_id ],
      name: "idx_merge_train_members_job_train",
      if_not_exists: true

    add_index :merge_trains,
      [ :state, :id ],
      name: "idx_merge_trains_state_id",
      if_not_exists: true
  end
end
