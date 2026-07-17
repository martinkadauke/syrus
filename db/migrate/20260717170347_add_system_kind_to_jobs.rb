class AddSystemKindToJobs < ActiveRecord::Migration[8.1]
  INDEX_NAME = "index_jobs_on_repository_id_system_kind_state"

  def up
    add_column :jobs, :system_kind, :string unless column_exists?(:jobs, :system_kind)
    add_index :jobs, [ :repository_id, :system_kind, :state ], name: INDEX_NAME unless index_exists?(:jobs, [ :repository_id, :system_kind, :state ], name: INDEX_NAME)
  end

  def down
    remove_index :jobs, name: INDEX_NAME if index_exists?(:jobs, name: INDEX_NAME)
    remove_column :jobs, :system_kind if column_exists?(:jobs, :system_kind)
  end
end
