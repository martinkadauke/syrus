class CreateInstanceVersions < ActiveRecord::Migration[8.1]
  def up
    return if table_exists?(:instance_versions)

    create_table :instance_versions, if_not_exists: true do |t|
      t.string :hostname, null: false
      t.string :role, null: false
      t.string :version, null: false
      t.datetime :started_at, null: false
      t.datetime :last_heartbeat_at
      t.datetime :finished_at
      t.string :outcome
      t.timestamps
    end

    unless index_exists?(:instance_versions, [ :hostname, :role ], unique: true)
      add_index :instance_versions, [ :hostname, :role ], unique: true
    end

    unless index_exists?(:instance_versions, :last_heartbeat_at)
      add_index :instance_versions, :last_heartbeat_at
    end

    unless index_exists?(:instance_versions, :finished_at)
      add_index :instance_versions, :finished_at
    end
  end

  def down
    drop_table :instance_versions if table_exists?(:instance_versions)
  end
end
