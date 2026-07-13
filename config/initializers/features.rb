Rails.application.config.after_initialize do
  unless Rails.env.test? ||
         SyrusVersion.sidecar_process? ||
         Features::SyncFromYaml.build_time_asset_precompile?
    Features::SyncFromYaml.call
  end
end
