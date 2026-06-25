Rails.application.config.after_initialize do
  Features::SyncFromYaml.call unless Rails.env.test? || Features::SyncFromYaml.build_time_asset_precompile?
end
