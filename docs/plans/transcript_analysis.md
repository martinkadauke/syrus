# Agent transcript improvement plan

_Captured 2026-06-06. Source data came from the production admin API,
not local development logs._

## Background

Recent production chat and run transcripts show agents losing time on
avoidable environment discovery, stale state, noisy logs, and incomplete
diagnostic APIs. The goal of this plan is to make agent work more
reliable and cheaper by improving the information Syrus gives agents
before and during a task, and by making operator-facing transcript
diagnostics easier to analyze.

## Evidence

The transcript audit sampled:

- All 5 production chats returned by `/api/v1/admin/chats`, totaling
  1,535 messages.
- Recent run metadata from `/api/v1/admin/runs`.
- Recent failed runs from `/api/v1/admin/runs?state=failed`.
- Recent agentic run transcript and artifact endpoints for runs such as
  `19195` and `19201`.

Observed patterns:

- Agents wasted turns discovering attached repositories or trying direct
  GitHub clones.
- Agents were confused when the `syrus-chat-sidecar` MCP tools were
  unavailable or not available inside delegated subagents.
- Large tool outputs consumed excessive context; 26 tool results were
  larger than 12 KB.
- Some runs spent a full agent turn recovering from missing or broken
  dependency setup.
- The transcript endpoint returned no useful parsed events for recent
  Codex sessions, while `/artifacts` had usable `JobLog` rows.
- Repeated operational failures, such as `rebase cap reached`, were
  classified as generic `application_error`.
- Grade logs were stored as many tiny chunks, making the failure signal
  hard to find.
- Agents sometimes inferred live system state from code or stale
  transcript context instead of querying Syrus state.

## Target State

Agents should start with explicit repo and Syrus-state context, have
clear MCP/tool availability, avoid large accidental context dumps, and
use reliable live-state tools when answering operational questions.
Operators should be able to inspect agent behavior through fast,
structured transcript APIs that work for both Claude and Codex runs.

## Workstreams

### 1. Make repository context explicit

Problem: Attached repositories are implicit. Agents sometimes try to
clone from GitHub or ask which repository to use even when the chat
already has an attached repo.

Plan:

- Add a repository context block to the initial chat prompt.
- Include repo slug, local workspace path, default branch, current
  branch, write permissions, credential mode, and attached documents.
- Explicitly instruct agents to use the provided workspace path instead
  of cloning from GitHub directly.
- Add a compact repository context payload to chat admin diagnostics so
  transcript audits can see what context the agent received.

Acceptance:

- New chat prompts include all attached repository paths and slugs.
- A request spec or service spec covers prompt rendering for chats with
  zero, one, and multiple repositories.
- A chat transcript no longer requires the agent to discover the primary
  workspace path through shell commands.

### 2. Clarify MCP and tool availability

Problem: Agents cannot tell whether a Syrus tool is unavailable because
the sidecar is down, because the tool is not exposed in the current
context, or because the task is running in a subagent without MCP access.

Plan:

- Add an MCP health/status field to the chat prompt and chat payload.
- Expose a small `mcp_health` or equivalent tool that reports available
  Syrus tools and sidecar state.
- Decide whether Syrus MCP tools are available to delegated subagents.
- If subagents cannot use Syrus MCP tools, add prompt guidance saying
  not to delegate work that requires those tools.

Acceptance:

- The agent can distinguish `tool missing`, `sidecar failed`, and
  `sidecar pending`.
- Chat diagnostics expose MCP status for each turn.
- Tests cover healthy and failed sidecar states.

### 3. Reduce accidental context burn

Problem: Agents repeatedly read large files, route dumps, and command
outputs when a smaller summary would have been enough.

Plan:

- Update chat prompts to prefer `rg`, targeted line ranges, and compact
  summaries over full file dumps.
- Add a repo-side summary tool for common discovery tasks:
  routes, models, frontend entry points, tests, workflow definitions,
  and key service classes.
- Add output caps or warnings for oversized tool results where feasible.
- Prefer repo-relative paths in chat-visible tool output.

Acceptance:

- Prompt instructions explicitly discourage full-file reads unless
  needed.
- The repository summary tool returns bounded, structured output.
- Tool output shown in chat trims workspace roots by default.

### 4. Make dependency setup reliable before agents run

Problem: Agents sometimes spend implementation turns recovering from
missing dependencies, Bundler cache permissions, or incomplete prepare
state.

Plan:

- Ensure prepare artifacts are materialized before grade loops and
  agentic retry steps begin.
- Route Bundler, npm, and related caches into the workflow workspace or
  Syrus data root, not system directories such as `/usr/local`.
- Record prepare state in a structured artifact that later steps can
  read.
- Teach prompts to inspect prepare status before reinstalling
  dependencies manually.

Acceptance:

- Prepare failures are visible as prepare failures, not hidden inside
  implementation or landing fix steps.
- A regression spec covers Bundler cache paths for prepared workspaces.
- Agents receive a clear setup status in the prompt or tool context.

### 5. Improve transcript APIs for Codex and JobLog fallback

Problem: `/api/v1/admin/runs/:id/transcript` can return no parsed events
for Codex sessions even when `/artifacts` contains usable transcript
rows. Artifact calls can also be slow for large runs.

Plan:

- Parse Codex transcript JSONL into the same event shape used by the
  transcript API.
- Add a `JobLog` fallback when an agent session is missing or
  unparseable.
- Add filters such as `kind=assistant_text,tool_call,tool_result`,
  `tail=N`, and `q=...`.
- Cache or persist parsed transcript summaries for large transcripts.

Acceptance:

- Codex and Claude runs both return useful transcript events.
- Transcript endpoint tests cover Codex JSONL, Claude JSONL, and JobLog
  fallback.
- Large transcript requests can fetch a filtered tail without loading
  every event.

### 6. Make failure classification actionable

Problem: Operational failures such as `rebase cap reached` and grader
failures are classified as generic application errors.

Plan:

- Add explicit classifications for:
  - `rebase_cap_reached`
  - `grader_failed`
  - `dependency_setup_missing`
  - `provider_auth`
  - `workspace_corrupt`
  - `disk_pressure`
- Attach a suggested next action to each classification:
  rebase, require reapproval, pause landing, rerun grade, retry after
  setup, or ask the operator.
- Surface classification and next action in the admin API and UI.

Acceptance:

- Rebase-cap failures are no longer `application_error`.
- Grader failures identify the failing grader and command.
- Admin API responses include a machine-readable suggested action.

### 7. Coalesce and summarize grade logs

Problem: Grade logs are stored as many tiny chunks, often thousands of
rows, which slows API calls and hides failures.

Plan:

- Group grade output by command and stream.
- Coalesce progress-only output such as RSpec dots.
- Extract failure summaries separately from raw logs.
- Show the summary first in the UI/API, with raw logs expandable or
  downloadable.

Acceptance:

- A failed RSpec grade exposes failing examples near the top of the
  payload.
- Raw logs remain available for deep debugging.
- Log row counts for normal grade runs are substantially lower.

### 8. Strengthen live-state instructions and tools

Problem: Agents sometimes answer from stale snapshots or infer live
state from code when they should query Syrus.

Plan:

- Add a chat/system prompt rule: use live Syrus state for operational
  questions before answering.
- Provide a compact live-state tool for jobs, epics, workflows, runs,
  landing blockers, queue state, and latest failures.
- Include freshness timestamps in live-state responses.
- Tell agents to ask once if no repository is attached instead of
  guessing.

Acceptance:

- Chat agents query live state before answering job, queue, landing, or
  workflow status questions.
- Live-state responses include enough detail to explain blockers without
  shelling into the production environment.
- Prompt tests cover the live-state guidance.

## Suggested Sequence

1. Add explicit repository context to chat prompts.
2. Add MCP health/status visibility.
3. Add live Syrus state tooling and prompt guidance.
4. Add Codex transcript parsing and JobLog fallback.
5. Coalesce grade logs and expose grade summaries.
6. Improve failure classification and suggested actions.
7. Harden dependency setup and prepare artifact handling.
8. Add bounded repo-summary tools and output caps.

This order front-loads the changes that immediately reduce agent
confusion, then improves diagnostics and classification, then hardens the
execution environment.

## Verification Plan

- Add focused request/service specs for prompt context, MCP status,
  transcript parsing, failure classification, and grade summaries.
- Run `bin/rspec` for backend changes.
- Run `bin/test-react` for UI or transcript-viewer changes.
- Exercise at least one production chat turn after deployment and
  confirm the transcript shows:
  - explicit repository context,
  - MCP health,
  - live-state query use for operational questions,
  - bounded tool output.

## Non-goals

- Do not replace the agent provider.
- Do not make chat depend on kubectl or Rails runner access.
- Do not remove raw transcript or raw grade logs; make them secondary to
  structured summaries.
- Do not treat prompt-only changes as sufficient when the missing
  information should be available as structured tool data.
