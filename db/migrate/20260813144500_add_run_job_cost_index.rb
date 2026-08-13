class AddRunJobCostIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :runs,
              [ :job_id, :cost_usd ],
              name: "idx_runs_job_cost",
              if_not_exists: true
  end
end
