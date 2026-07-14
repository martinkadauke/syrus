class AddMainBranchRepairEnabledToRepositories < ActiveRecord::Migration[8.1]
  def up
    unless column_exists?(:repositories, :main_branch_health_enabled)
      add_column :repositories, :main_branch_health_enabled, :boolean, null: false, default: true
    end

    unless column_exists?(:repositories, :main_branch_repair_enabled)
      add_column :repositories, :main_branch_repair_enabled, :boolean, null: false, default: true
    end

    execute <<~SQL.squish
      UPDATE repositories
      SET main_branch_repair_enabled = 0
      WHERE upstream_repository_id IS NOT NULL
        OR (
          upstream_owner IS NOT NULL
          AND upstream_owner <> ''
          AND upstream_name IS NOT NULL
          AND upstream_name <> ''
        )
    SQL
  end

  def down
    remove_column :repositories, :main_branch_repair_enabled if column_exists?(:repositories, :main_branch_repair_enabled)
    remove_column :repositories, :main_branch_health_enabled if column_exists?(:repositories, :main_branch_health_enabled)
  end
end
