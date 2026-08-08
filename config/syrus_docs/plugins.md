# Plugins

Syrus plugins are Rails Engine gems that register extension point providers at
boot through `Syrus::PluginRegistry`. The registry currently supports:

- `agent_provider`
- `chat_provider`
- `mcp_tool_set`
- `input_source`
- `test_result_parser`
- `coverage_analyzer`
- `preview_provider`
- `admin_page`
- `chat_mcp_tool_set`

Operators can inspect the registered plugins from **Admin → Plugins**
(`/admin/plugins`). The page shows each plugin's name, version, enabled state,
default enabled state, disableability policy, category, author/source metadata
when available, and every class registered for an extension point. Disableable
installed plugins can be enabled or disabled live; new requests and sidecars use
the latest `PluginRecord` state through `PluginRegistry.providers_for`.

Availability is reported per extension point. Agent and chat providers run the
provider class's `.available?` check. Input sources show how many repository
`InputSource` records use that source class. MCP tool sets are listed as
registered because their runtime availability depends on the repository context
that invokes the sidecar. Test result parsers and coverage analyzers are listed
as registered parser classes.

Plugin install and uninstall remain manual operations: edit the Gemfile, run
Bundler, run migrations if the plugin ships any, and restart the Rails
processes so plugin engine initializers register with the in-memory registry.
Non-disableable plugins are forced enabled and should be reserved for core
runtime pieces.

Bundled plugins:

- `core_tools` — non-disableable core workflow MCP tools.
- `claude_agent` / `codex_agent` — default-enabled workflow and chat providers.
- `github_source` — default-enabled GitHub issue/PR polling source.
- `linear_source` — installed but disabled by default until configured.
- `syrus_dev` — installed but disabled by default. It owns Syrus-development-only
  diagnostics such as Admin → Performance and the `read_performance_diagnostics`
  / `read_syrus_logs` workflow MCP tools. Enable it only on instances where
  agents or operators should inspect Syrus's own production behavior.
