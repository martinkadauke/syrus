class AddInstallationAndAgentProviderToRepositoryMemberships < ActiveRecord::Migration[8.1]
  def up
    unless column_exists?(:repository_memberships, :installation_id)
      add_column :repository_memberships, :installation_id, :bigint
    end
    unless index_exists?(:repository_memberships, :installation_id)
      add_index :repository_memberships, :installation_id,
        name: "index_repository_memberships_on_installation_id"
    end
    unless foreign_key_exists?(:repository_memberships, :installations, column: :installation_id)
      add_foreign_key :repository_memberships, :installations, column: :installation_id, on_delete: :nullify
    end

    unless column_exists?(:repository_memberships, :agent_provider)
      add_column :repository_memberships, :agent_provider, :string
    end
  end

  def down
    remove_foreign_key :repository_memberships, column: :installation_id if foreign_key_exists?(:repository_memberships, :installations, column: :installation_id)
    remove_index :repository_memberships, name: "index_repository_memberships_on_installation_id" if index_exists?(:repository_memberships, :installation_id)
    remove_column :repository_memberships, :installation_id if column_exists?(:repository_memberships, :installation_id)
    remove_column :repository_memberships, :agent_provider if column_exists?(:repository_memberships, :agent_provider)
  end
end
