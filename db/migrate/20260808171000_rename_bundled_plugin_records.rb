class RenameBundledPluginRecords < ActiveRecord::Migration[8.1]
  RENAMES = {
    "syrus-claude-agent" => "claude_agent",
    "syrus-codex-agent" => "codex_agent",
    "syrus_core_tools" => "core_tools",
    "syrus-github-source" => "github_source",
    "syrus-linear-source" => "linear_source"
  }.freeze

  def up
    rename_plugin_records(RENAMES)
  end

  def down
    rename_plugin_records(RENAMES.invert)
  end

  private

  def rename_plugin_records(mapping)
    mapping.each do |old_name, new_name|
      old_record = PluginRecord.find_by(name: old_name)
      next unless old_record

      new_record = PluginRecord.find_by(name: new_name)
      if new_record
        new_record.update!(
          enabled: old_record.enabled,
          default_enabled: old_record.default_enabled,
          disableable: old_record.disableable,
          config: new_record.config.to_h.deep_merge(old_record.config.to_h)
        )
        old_record.destroy!
      else
        old_record.update!(name: new_name)
      end
    end
  end
end
