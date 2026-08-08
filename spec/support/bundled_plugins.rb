# Re-register bundled plugins before each example so registry-backed model
# validations and settings payloads work correctly in tests.
#
# config/initializers/plugin_registry.rb resets the registry via
# after_initialize in test mode. This before hook restores the bundled
# providers before each example.
#
# Examples tagged :reset_plugin_registry (i.e. plugin_registry_spec) opt out
# so their around block gets a genuinely empty registry. RSpec hook ordering is
# around-pre → before → example, so the before hook would otherwise fire after
# the around reset and repopulate the registry before the example body runs.
RSpec.configure do |config|
  config.before do |example|
    next if example.metadata[:reset_plugin_registry]

    registered_names = Syrus::PluginRegistry.registered_names

    unless registered_names.include?("claude_agent")
      Syrus::PluginRegistry.register(
        name:            "claude_agent",
        version:         SyrusClaudeAgent::VERSION,
        default_enabled: true,
        disableable:     true,
        category:        "agent_provider",
        provides: {
          agent_provider: AgentProviders::Claude,
          chat_provider:  ChatProviders::Claude
        }
      )
    end

    unless registered_names.include?("codex_agent")
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

    unless registered_names.include?("core_tools")
      Syrus::PluginRegistry.register(
        name:            "core_tools",
        version:         SyrusCoreTools::VERSION,
        default_enabled: true,
        disableable:     false,
        category:        "core",
        provides: { mcp_tool_set: SyrusMcp::CoreToolSet }
      )
    end

    unless registered_names.include?("github_source")
      Syrus::PluginRegistry.register(
        name:            "github_source",
        version:         SyrusGithubSource::VERSION,
        default_enabled: true,
        disableable:     true,
        category:        "input_source",
        provides: { input_source: InputSources::Github }
      )
    end

    unless registered_names.include?("linear_source")
      Syrus::PluginRegistry.register(
        name:            "linear_source",
        version:         SyrusLinearSource::VERSION,
        default_enabled: false,
        disableable:     true,
        category:        "input_source",
        provides: { input_source: InputSources::Linear }
      )
    end

    unless registered_names.include?("syrus_dev")
      Syrus::PluginRegistry.register(
        name:            "syrus_dev",
        version:         SyrusDev::VERSION,
        default_enabled: false,
        disableable:     true,
        category:        "dev",
        frontend: {
          routes: {
            "syrus_dev/AdminPerformance" => "app/frontend/routes/AdminPerformance.tsx"
          },
          i18n: [ "app/frontend/i18n/locales/*/syrus_dev.json" ]
        },
        routes: [
          {
            verb: "GET",
            path: "/api/v1/app/admin/performance",
            controller: "api/v1/app/admin/performance#show"
          },
          {
            verb: "GET",
            path: "/api/v1/admin/performance",
            controller: "api/v1/admin/performance#show"
          },
          {
            verb: "GET",
            path: "/admin/performance",
            controller: "spa#show"
          }
        ],
        provides: {
          admin_page:   SyrusDev::AdminPages,
          mcp_tool_set: SyrusDev::WorkflowToolSet
        }
      )
    end

    Syrus::PluginRegistry.all_plugins
  end
end
