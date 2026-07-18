# MCP tool capability and memory policy

Captured July 18, 2026.

## Goal

Make Syrus deliberate about which MCP tools an agent can use, based on
what the agent is doing, which surface invoked it, what the user is allowed
to see, and what memory should be available.

The target outcome is that tool access feels powerful without being
surprising:

- chat agents can plan, inspect, remember, and propose work;
- implementation agents can do the current Job and no more;
- infrastructure agents can inspect operational evidence without mutating
operator state;
- admin-only tools stay admin-only;
- memory makes the system compound over time without leaking context across
users, repositories, Jobs, or unrelated chats.

## Why This Matters

Today Syrus has several MCP tool surfaces:

- workflow-side tools under `SyrusMcp::Sidecar`;
- chat tools under `SyrusChatMcp::Sidecar`;
- deferred chat tools for larger read operations;
- admin/local/coding-mode tool subsets.

This has grown organically. The next step is a central capability policy:
tools should not be registered merely because a sidecar can expose them.
They should be registered because the current agent context grants a specific
capability within a specific scope.

Memory is part of that same policy. A mediocre memory system is worse than
none: it can make agents confidently use stale, cross-scope, or private
context. A great memory system can make Syrus feel like a continuously
improving collaborator.

## Existing Pieces To Reuse

### Infrastructure Job Shape

`main_grader` is the closest existing pattern:

- represented as a normal `Job`;
- infrastructure-flavored;
- repository-scoped;
- produces signal instead of commits;
- does not open PRs;
- auto-closes when complete;
- has queue/concurrency rules separate from normal implementation work.

An agent-insight job should follow this shape.

### Workflow Sidecar Base

`SyrusMcp::Sidecar` is the right base for non-chat Workflow Runs because it
is run-scoped. Existing tools to reuse or model after:

- `read_live_state`;
- `read_memory`;
- `submit_summary`;
- `submit_test_plan`;
- `submit_adversarial_review`;
- `report_main_concern`.

For insight jobs, we likely add a new structured write tool such as
`submit_insight`, modeled after `submit_adversarial_review` and
`report_main_concern`.

### Read-Only Inspection Tools

The chat MCP side already has useful read tools. Their payload logic should
be reused, but their authorization layer should not be reused as-is.

Candidates:

- `read_job`;
- `list_job_workflows`;
- `read_workflow`;
- `read_run_transcript`;
- `get_job_diff`;
- `search_jobs`;
- `list_jobs`;
- `read_chat_messages`;
- `search_chats`;
- `list_chats`;
- `repo_info`;
- `read_pr`;
- `list_open_prs`;
- `list_open_issues`;
- `read_queue`;
- `get_spending`;
- `search_syrus_docs`.

These should move toward shared payload builders that can be wrapped by
surface-specific authorization.

### Tools Not To Reuse For Insight Jobs

Insight jobs should not receive mutation tools:

- approve/cancel/retry/rebase/update Job;
- create proposal/Job/Epic;
- mutate dependencies;
- pause/resume queue;
- admin mutation tools;
- local shell/write tools outside the assigned workspace;
- whiteboard or drawing tools.

The insight job should write only structured insight records/artifacts.

## Capability Axes

Tool access should be computed from a context object, not hardcoded per
binary.

Important dimensions:

- **Surface:** chat, workflow, infrastructure job, admin console, CLI,
  desktop.
- **Intent:** explore, propose, implement, grade, land, repair, inspect,
  analyze.
- **User role:** normal user, repository owner/assignee, admin.
- **Repository scope:** attached repository, current Job repository,
  current Epic graph, all repositories owned by user, whole instance.
- **Object scope:** allowed Job IDs, Workflow IDs, Run IDs, ChatSession IDs,
  Epic IDs, PR numbers.
- **Mutability:** read-only, write structured artifacts, create proposals,
  mutate Jobs, mutate GitHub, mutate system/admin state.
- **Memory scope:** none, current turn, current chat, current Job, current
  repository, current user, current team, whole instance.

The sidecar should ask a single policy object what tools to expose:

```ruby
McpToolPolicy.for(context).allowed_tools
```

The context should be explicit:

```ruby
{
  surface: "workflow",
  profile: "agent_insight",
  user: user,
  repository: repository,
  job: job,
  workflow: workflow,
  run: run,
  allowed_job_ids: [...],
  allowed_workflow_ids: [...],
  allowed_run_ids: [...],
  allowed_chat_session_ids: [...],
  allowed_memory_scopes: [...]
}
```

## Proposed Tool Profiles

### Chat: Planning

Available:

- inspect attached repositories;
- read/search the current user's Jobs, Epics, Workflows, and Runs within
  allowed repository scope;
- read current chat history and relevant bookmarked messages;
- create proposals;
- attach repositories/documents;
- read/write scoped memory;
- ask follow-up questions.

Not available:

- direct admin mutations;
- arbitrary local filesystem mutation;
- unrelated users' Jobs/chats;
- landing/rebase/queue mutation unless explicitly exposed through a
  user-facing action.

### Chat: Admin

Available:

- planning tools;
- admin read tools;
- queue/system inspection tools;
- instance-level metrics and diagnostics.

Mutation tools should remain narrow, named, and auditable. Admin status
should not mean "all tools, all the time."

### Workflow: Implementation

Available:

- current Job/Workflow/Run state;
- current repository workspace;
- dependency and Epic context for the current Job;
- read-only relevant memories;
- submit summary/test plan;
- implementation tools provided by the agent provider.

Not available:

- unrelated chats;
- unrelated Jobs;
- admin tools;
- mutation of other Jobs or Epics.

### Workflow: Grading

Available:

- repository workspace;
- current Workflow/Run state;
- configured grader metadata;
- prior successful grader cache for the same SHA when allowed.

Not available:

- user memory writes;
- PR mutation;
- unrelated workflow transcripts.

### Workflow: Landing/Rebase/Merge Train

Available:

- current PR/branch/merge-train members;
- scoped GitHub operations needed for landing;
- grader outputs for this landing attempt;
- dependency graph relevant to the PR stack or Epic train.

Not available:

- arbitrary job mutation;
- chat history unrelated to landing;
- unrelated repositories.

### Infrastructure: Main Grader

Available:

- repository checkout at default branch SHA;
- configured graders;
- main-branch health write path.

No commits, no PRs, no chat memory writes.

### Infrastructure: Agent Insight

Available:

- assigned repository checkout;
- scoped transcripts/logs/jobs/chats;
- repo metadata;
- queue/run diagnostics relevant to the insight window;
- read-only memory relevant to the repository and user/team;
- `submit_insight`.

Not available:

- arbitrary cross-repo transcript reads;
- job mutation;
- GitHub mutation;
- broad admin mutation;
- user-private memories unless explicitly in scope.

## Memory Model

Memory should be treated as a capability with the same rigor as tools.

### Memory Classes

1. **Turn memory**
   - Exists only inside the provider context window.
   - Not persisted by Syrus.
   - Useful for short-lived reasoning.

2. **Chat memory**
   - Belongs to a `ChatSession`.
   - Includes pinned context, bookmarks, attachments, queued messages, and
     conversation summary.
   - Readable by agents in that chat.
   - Not automatically available to unrelated Jobs.

3. **Job memory**
   - Belongs to a `Job`/`Workflow`/`Run`.
   - Includes artifacts, summaries, test plans, grader outputs, decisions,
     failure classifications, and handoff notes.
   - Available to later retries/feedback/landing for the same Job.

4. **Repository memory**
   - Durable facts about how to work in the repository:
     - setup quirks;
     - flaky tests;
     - common commands;
     - known architecture notes;
     - preferred implementation conventions;
     - recurring agent mistakes;
     - `.syrus.yml` improvement suggestions.
   - Available to chat and workflow agents scoped to that repository.
   - Should have provenance and freshness metadata.

5. **User memory**
   - Operator preferences:
     - language/style;
     - preferred agent provider;
     - review strictness;
     - tolerance for risk;
     - UI preferences.
   - Should not leak to other users.

6. **Team/instance memory**
   - Shared operational knowledge:
     - cluster constraints;
     - release process;
     - admin policies;
     - common production failure modes.
   - Admin-controlled or explicitly shared.

7. **Insight memory**
   - Suggestions generated by agent-insight jobs.
   - Includes evidence references, proposed prompt, affected repository,
     confidence, severity, and status.
   - Can become repository memory only after operator acceptance.

### Memory Permissions

Memory access should distinguish:

- `memory.read.chat`;
- `memory.write.chat`;
- `memory.read.job`;
- `memory.write.job`;
- `memory.read.repository`;
- `memory.write.repository`;
- `memory.read.user`;
- `memory.write.user`;
- `memory.read.team`;
- `memory.write.team`;
- `memory.read.instance`;
- `memory.write.instance`;
- `memory.write.insight`.

Most agents should read more than they can write.

For example:

- implementation agents can read repository memory and write Job artifacts;
- chat agents can write chat memory and propose repository memories;
- insight agents can read scoped repository/job/chat evidence and write
  insight suggestions, but not directly mutate durable repository memory;
- admin insight jobs can read instance diagnostics but still write structured
  suggestions rather than making changes.

### Memory Provenance

Every durable memory should record:

- source type: chat, job, run, manual, insight, admin;
- source object ID;
- repository/user/team scope;
- author: user or agent;
- confidence;
- created_at and last_verified_at;
- optional expires_at;
- evidence references.

Agents should see provenance when memory may affect behavior. Example:

> Repository memory from JOB-1420, verified 12 days ago: `bin/rspec` can
> exceed 20 minutes with coverage enabled.

### Memory Freshness

Stale memory is dangerous. Repository memory should be invalidated or
downranked when:

- `.syrus.yml` changes;
- dependency lockfiles change;
- build/test commands change;
- the relevant file paths disappear;
- an operator marks it obsolete;
- multiple later runs contradict it.

Insight jobs can help find stale memory by comparing old advice to recent
successful/failed runs.

### Memory Injection Strategy

Do not dump all memory into every prompt.

Use tiers:

1. **Always injected:** current Job/Workflow/Run identity, repository slug,
   current objective, critical constraints.
2. **Relevant summary:** a compact list of high-confidence repository/job
   memories selected by scope and recency.
3. **On-demand tools:** MCP tools to read full memory records, evidence,
   transcripts, and logs.

This keeps prompts small while still giving the agent a path to deeper
context.

### Memory Safety Rules

- Cross-user memory is forbidden unless explicitly shared through a team or
  admin scope.
- Cross-repository memory is opt-in and should be rare.
- Chat memories are private to that chat unless promoted.
- Insight jobs can suggest memory promotion but should not silently promote
  it.
- Memory writes should be structured and auditable.
- Agents should never treat memory as more authoritative than current repo
  state, current tests, or explicit user instructions.

## Insight Jobs

Agent-insight jobs should be infrastructure jobs that inspect recent agent
struggles and propose fixes.

Inputs:

- repository;
- time window;
- sampled Job/Workflow/Run IDs;
- sampled chat IDs;
- relevant memory scopes;
- current codebase checkout.

Outputs:

- structured insights;
- evidence references;
- suggested operator-facing prompt;
- optional suggested `.syrus.yml` diff direction;
- optional suggested Syrus product/harness fix when the repository is Syrus.

Example:

```json
{
  "title": "RSpec timeouts are repeatedly treated as broken main",
  "category": "grader_timeout_policy",
  "severity": "high",
  "repository_id": 12,
  "evidence": [
    { "run_id": 46063, "kind": "transcript" },
    { "job_id": 1642, "kind": "failure" }
  ],
  "suggested_prompt": "Update .syrus.yml so the rspec grader timeout is 40 minutes...",
  "confidence": 0.82
}
```

If the repository is `tkadauke/syrus`, the suggested prompt may target
Syrus itself. If the repository is `tkadauke/raytracer`, the suggestion
should usually target that repository's `.syrus.yml`, docs, or tests.

## Defense In Depth

Filtering tools at registration time is not enough.

Every tool must independently validate that requested IDs are inside the
current context's allowed scope.

Bad:

```ruby
register_tool(ReadRunTranscriptTool) if profile.agent_insight?
```

Good:

```ruby
register_tool(ReadRunTranscriptTool)
ReadRunTranscriptTool.call(run_id:) # rejects unless run_id is in scope
```

This matters for tools like `read_run_transcript`, where arbitrary IDs could
otherwise leak unrelated user or repository history.

## Work Plan

### M1 - Define Capability Context

- Add a `McpToolContext` object used by chat and workflow sidecars.
- Include surface, profile, user, repository, job, workflow, run, role, and
  explicit allowed object IDs.
- Add specs for normal user/admin contexts.

### M2 - Centralize Tool Policy

- Add `McpToolPolicy.for(context)`.
- Register tools through the policy instead of per-sidecar constants.
- Preserve existing behavior while making the decision visible and testable.

### M3 - Extract Shared Read Payloads

- Extract payload builders from chat read tools:
  - Job;
  - Workflow;
  - Run transcript;
  - Job diff;
  - Chat messages;
  - Repository info;
  - Queue.
- Keep current chat tools as wrappers around shared readers.

### M4 - Add Scoped Authorization For Infrastructure Jobs

- Add an insight/main-grader-safe authorization layer.
- Scope by repository, user, and explicit evidence IDs.
- Add negative tests proving unrelated Job/Run/Chat IDs are rejected.

### M5 - Formalize Memory Capabilities

- Define memory scopes and read/write permissions.
- Add provenance/freshness metadata where missing.
- Split memory writes into direct writes and proposals.
- Ensure implementation agents cannot silently write user/team/repository
  memory.

### M6 - Add Agent Insight Job Type

- Add an infrastructure `agent_insight` Job kind and Workflow trigger.
- Use a no-commit/no-PR workflow.
- Provide repository checkout plus scoped evidence tools.
- Add `submit_insight`.
- Auto-close successful insight jobs like main-grader jobs.

### M7 - Operator UI For Insights

- List insight suggestions by repository.
- Show evidence links and proposed prompt.
- Allow dismiss, accept, and create Job from suggestion.
- Allow accepted suggestions to become repository memory when appropriate.

### M8 - Memory Retrieval And Injection

- Add a memory retrieval layer that selects compact context by current
  objective.
- Keep full memory/evidence available through MCP tools.
- Add regression tests for prompt size and scope boundaries.

## Open Questions

- Should repository memory be editable directly by operators, or only through
  accepted suggestions?
- Should insight jobs run on a schedule, after failures, manually, or all
  three?
- What is the default time window and evidence cap for insight jobs?
- Do admin insight jobs get instance-wide read access, or should they still
  be repository-scoped by default?
- How aggressively should stale memory be hidden vs merely downranked?

