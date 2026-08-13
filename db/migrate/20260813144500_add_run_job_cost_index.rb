class AddRunJobCostIndex < ActiveRecord::Migration[8.1]
  def change
    columns = [ :job_id, :cost_usd ]

    unless index_exists?(:runs, columns, name: "idx_runs_job_cost")
      add_index :runs,
                columns,
                name: "idx_runs_job_cost"
    end
  end
end
