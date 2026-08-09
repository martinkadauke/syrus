class AddRunsJobIdIdIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :runs,
      [ :job_id, :id ],
      name: "idx_runs_job_id_id",
      if_not_exists: true
  end
end
