class AddLastCiHandledShaToJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :jobs, :last_ci_handled_sha, :string
  end
end
