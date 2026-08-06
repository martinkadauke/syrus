class AddWorkerStorageKeyToWorkflows < ActiveRecord::Migration[8.1]
  def change
    add_column :workflows, :worker_storage_key, :string unless column_exists?(:workflows, :worker_storage_key)
    add_index :workflows, :worker_storage_key unless index_exists?(:workflows, :worker_storage_key)
  end
end
