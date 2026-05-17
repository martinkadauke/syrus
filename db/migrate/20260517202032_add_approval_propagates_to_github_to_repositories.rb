class AddApprovalPropagatesToGithubToRepositories < ActiveRecord::Migration[8.1]
  def up
    return if column_exists?(:repositories, :approval_propagates_to_github)

    add_column :repositories, :approval_propagates_to_github, :boolean
  end

  def down
    return unless column_exists?(:repositories, :approval_propagates_to_github)

    remove_column :repositories, :approval_propagates_to_github
  end
end
