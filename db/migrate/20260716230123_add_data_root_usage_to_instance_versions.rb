class AddDataRootUsageToInstanceVersions < ActiveRecord::Migration[8.1]
  def up
    add_column :instance_versions, :data_root_used_percent, :integer unless column_exists?(:instance_versions, :data_root_used_percent)
    add_column :instance_versions, :data_root_available_bytes, :bigint unless column_exists?(:instance_versions, :data_root_available_bytes)
    add_column :instance_versions, :data_root_total_bytes, :bigint unless column_exists?(:instance_versions, :data_root_total_bytes)
    add_column :instance_versions, :data_root_path, :string unless column_exists?(:instance_versions, :data_root_path)
  end

  def down
    remove_column :instance_versions, :data_root_used_percent if column_exists?(:instance_versions, :data_root_used_percent)
    remove_column :instance_versions, :data_root_available_bytes if column_exists?(:instance_versions, :data_root_available_bytes)
    remove_column :instance_versions, :data_root_total_bytes if column_exists?(:instance_versions, :data_root_total_bytes)
    remove_column :instance_versions, :data_root_path if column_exists?(:instance_versions, :data_root_path)
  end
end
