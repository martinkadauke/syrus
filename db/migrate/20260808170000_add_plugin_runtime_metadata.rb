class AddPluginRuntimeMetadata < ActiveRecord::Migration[8.1]
  def change
    add_column :plugin_records, :default_enabled, :boolean, null: false, default: true, if_not_exists: true
    add_column :plugin_records, :disableable, :boolean, null: false, default: true, if_not_exists: true
  end
end
