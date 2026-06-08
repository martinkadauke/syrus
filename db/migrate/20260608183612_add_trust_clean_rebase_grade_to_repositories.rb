class AddTrustCleanRebaseGradeToRepositories < ActiveRecord::Migration[8.1]
  def up
    unless column_exists?(:repositories, :trust_clean_rebase_grade)
      add_column :repositories, :trust_clean_rebase_grade, :boolean, default: false, null: false
    end
  end

  def down
    remove_column :repositories, :trust_clean_rebase_grade if column_exists?(:repositories, :trust_clean_rebase_grade)
  end
end
