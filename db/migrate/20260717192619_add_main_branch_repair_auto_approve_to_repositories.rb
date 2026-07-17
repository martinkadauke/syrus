class AddMainBranchRepairAutoApproveToRepositories < ActiveRecord::Migration[8.1]
  def up
    unless column_exists?(:repositories, :main_branch_repair_auto_approve)
      add_column :repositories, :main_branch_repair_auto_approve, :boolean, null: false, default: false
    end
  end

  def down
    remove_column :repositories, :main_branch_repair_auto_approve if column_exists?(:repositories, :main_branch_repair_auto_approve)
  end
end
