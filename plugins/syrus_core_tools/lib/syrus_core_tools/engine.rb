module SyrusCoreTools
  class Engine < ::Rails::Engine
    config.after_initialize do
      Syrus::PluginRegistry.register(
        name:            "syrus_core_tools",
        version:         SyrusCoreTools::VERSION,
        default_enabled: true,
        disableable:     false,
        category:        "core",
        provides: { mcp_tool_set: SyrusMcp::CoreToolSet }
      )
    end
  end
end
