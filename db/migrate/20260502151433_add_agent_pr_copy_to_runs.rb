class AddAgentPrCopyToRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :runs, :agent_pr_title, :string
    add_column :runs, :agent_pr_body, :text
    add_column :runs, :agent_summary, :text
  end
end
