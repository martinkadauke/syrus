module SyrusLinearSource
  class Engine < ::Rails::Engine
    config.after_initialize do
      Syrus::PluginRegistry.register(
        name:            "syrus-linear-source",
        version:         SyrusLinearSource::VERSION,
        default_enabled: false,
        disableable:     true,
        category:        "input_source",
        provides: { input_source: InputSources::Linear }
      )
    end
  end
end
