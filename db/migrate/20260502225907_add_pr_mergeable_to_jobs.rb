class AddPrMergeableToJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :jobs, :pr_mergeable, :boolean
    add_column :jobs, :pr_mergeable_checked_at, :datetime
  end
end
