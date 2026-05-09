class AddAgentProviderToRepositories < ActiveRecord::Migration[8.1]
  def change
    add_column :repositories, :agent_provider, :string
  end
end
