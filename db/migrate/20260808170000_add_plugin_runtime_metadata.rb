class AddPluginRuntimeMetadata < ActiveRecord::Migration[8.1]
  def change
    return unless table_exists?(:plugin_records)

    unless column_exists?(:plugin_records, :default_enabled)
      add_column :plugin_records, :default_enabled, :boolean, null: false, default: true
    end

    unless column_exists?(:plugin_records, :disableable)
      add_column :plugin_records, :disableable, :boolean, null: false, default: true
    end
  end
end
