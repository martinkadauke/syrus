class AddAgentArtifactsToJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :jobs, :agent_diff, :text
    add_column :jobs, :agent_turns, :integer
  end
end
