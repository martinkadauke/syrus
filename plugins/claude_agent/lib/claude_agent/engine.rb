module SyrusClaudeAgent
  class Engine < ::Rails::Engine
    # after_initialize runs after Zeitwerk is fully active, ensuring
    # Syrus::PluginRegistry (autoloaded from lib/) is resolvable.
    config.after_initialize do
      Syrus::PluginRegistry.register(
        name:            "claude_agent",
        version:         SyrusClaudeAgent::VERSION,
        default_enabled: true,
        disableable:     true,
        category:        "agent_provider",
        provides: { agent_provider: AgentProviders::Claude }
      )
    end
  end
end
