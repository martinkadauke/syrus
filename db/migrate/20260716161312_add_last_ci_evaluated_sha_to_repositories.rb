class AddLastCiEvaluatedShaToRepositories < ActiveRecord::Migration[8.1]
  def up
    unless column_exists?(:repositories, :last_ci_evaluated_sha)
      add_column :repositories, :last_ci_evaluated_sha, :string
    end
  end

  def down
    if column_exists?(:repositories, :last_ci_evaluated_sha)
      remove_column :repositories, :last_ci_evaluated_sha
    end
  end
end
