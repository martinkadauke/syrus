class AddAgentOutcomeToJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :jobs, :agent_outcome, :string
  end
end
