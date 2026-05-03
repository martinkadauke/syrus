class AddAgentMaxTurnsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :agent_max_turns, :integer, default: 200, null: false
  end
end
