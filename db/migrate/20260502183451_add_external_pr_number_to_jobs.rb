class AddExternalPrNumberToJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :jobs, :external_pr_number, :integer
    add_index :jobs, :external_pr_number
  end
end
