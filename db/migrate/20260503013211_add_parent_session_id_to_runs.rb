class AddParentSessionIdToRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :runs, :parent_session_id, :string
    add_index :runs, :parent_session_id
  end
end
