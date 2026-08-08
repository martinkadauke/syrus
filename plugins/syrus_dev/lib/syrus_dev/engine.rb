module SyrusDev
  class Engine < ::Rails::Engine
    config.after_initialize do
      Syrus::PluginRegistry.register(
        name:            "syrus_dev",
        version:         SyrusDev::VERSION,
        default_enabled: false,
        disableable:     true,
        category:        "dev",
        description:     "Syrus development diagnostics and internal tooling.",
        provides: {
          admin_page:   SyrusDev::AdminPages,
          mcp_tool_set: SyrusDev::WorkflowToolSet
        }
      )
    end
  end
end
