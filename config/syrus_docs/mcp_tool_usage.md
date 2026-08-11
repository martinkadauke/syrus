# MCP Tool Usage

Syrus records MCP tool invocations from workflow agents and chat agents in
`mcp_tool_usages`. The table stores normalized tool identity, surface
(`workflow` or `chat`), server name when the provider exposes one, provider and
session identifiers, linked Job/Workflow/Run or ChatSession ids, user/repository
ids when derivable, start/completion timestamps, status, error flag, a bounded
error summary, and input/result byte counts.

The usage recorder intentionally does not persist full tool inputs or results.
Detailed transcript rendering remains backed by the existing run transcript and
chat message records.

Operators can inspect aggregate usage through:

- `GET /api/v1/app/admin/mcp_tool_usage`
- `GET /api/v1/admin/mcp_tool_usage`

Query parameters:

- `start` / `end`: ISO8601 time window. Defaults to the last 7 days and caps at
  90 days.
- `surface`: optional `workflow` or `chat` filter.
- `limit`: maximum rows returned for top-tool and error-rate sections, capped at
  100.

The response includes top tools, unused currently advertised tools for the
selected surface, error rates by tool, and chat-vs-workflow usage breakdown.

Tool exposure metadata is declared in `McpToolRegistry`. Use
`McpToolRegistry.summaries(surface: ..., tier: ...)` when docs or usage payloads
need authoritative tool profile data such as surface, tier, admin-only status,
feature flag gates, required roles/capabilities, and read-only vs mutation
classification.

Workflow-sidecar health is intentionally visible in `JobLog` for agentic steps
that require MCP submission tools such as `submit_summary` or
`submit_test_plan`. Look for `[mcp_config]`, `[mcp_sidecar]`,
`[mcp_tools_init]`, `[mcp_required]`, `[mcp_required_health]`, and
`[mcp_sidecar_stderr]` rows when debugging "agent succeeded but did not call the
required tool" failures. These rows show the generated MCP config path,
forwarded env key names, sidecar startup/tool advertisement, Claude's init-time
tool list, transcript evidence for whether the required tool was available or
called, and the sidecar stderr tail.

Tool implementations live under `Mcp::Tools`, and the stdio server processes
are built through the shared `Mcp::Sidecar` infrastructure. Protocol-visible
server names remain stable: `syrus-chat-sidecar`,
`syrus-chat-deferred-sidecar`, and `syrus-mcp-sidecar`.
