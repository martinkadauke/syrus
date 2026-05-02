class AddArchivedAtToRepositories < ActiveRecord::Migration[8.1]
  def change
    add_column :repositories, :archived_at, :datetime
    add_index :repositories, :archived_at
  end
end
