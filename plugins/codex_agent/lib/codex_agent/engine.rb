module SyrusCodexAgent
  class Engine < ::Rails::Engine
    # after_initialize runs after Zeitwerk is fully active, ensuring
    # Syrus::PluginRegistry (autoloaded from lib/) is resolvable.
    config.after_initialize do
      Syrus::PluginRegistry.register(
        name:            "codex_agent",
        version:         SyrusCodexAgent::VERSION,
        default_enabled: true,
        disableable:     true,
        category:        "agent_provider",
        provides: {
          agent_provider: AgentProviders::Codex,
          chat_provider:  ChatProviders::Codex
        }
      )
    end
  end
end
