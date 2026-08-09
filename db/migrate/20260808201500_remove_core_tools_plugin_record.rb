class RemoveCoreToolsPluginRecord < ActiveRecord::Migration[8.1]
  def up
    PluginRecord.where(name: [ "core_tools", "syrus_core_tools" ]).delete_all
  end

  def down
    PluginRecord.find_or_create_by!(name: "core_tools") do |record|
      record.enabled = true
      record.default_enabled = true if record.has_attribute?(:default_enabled)
      record.disableable = false if record.has_attribute?(:disableable)
      record.config = {}
    end
  end
end
