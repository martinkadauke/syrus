# Syrus Roadmap

Detailed milestone breakdown. Each milestone tracks one GitHub issue.

The build order is opinionated: **M3 must work before M4 starts.** The whole
premise of this project is that the deterministic harness is the load-bearing
piece — if `clone → branch → empty-commit → PR → cleanup` is flaky, swapping
in an AI agent only adds entropy. Get the slave's mechanics right first.

---

## M0 — Rails scaffold

Bootstrap a working Rails 8 app that boots locally and in CI. No domain logic.

**Deliverables**
- `rails new syrus --css=tailwind --javascript=importmap` — SQLite for
  dev/test, MySQL configured for `production` in `config/database.yml`
- Solid Queue wired up (Rails 8 default); one no-op job runs end-to-end via
  `bin/jobs`
- `Procfile.dev` runs `web` + `worker` (`bin/jobs`) together; `bin/dev`
  boots both
- `Gemfile` pins Rails 8, sqlite3 (default), mysql2 (`:production`), devise
  (or rodauth — TBD); Solid Queue / Cache / Cable ship in Rails 8
- `.github/workflows/ci.yml` runs `rspec` + `rubocop` against MySQL service
- `README` updated with `bin/setup` instructions

**Out of scope:** Auth UI, models, deploy.

---

## M1 — Data model

Define the domain. No background work yet — just migrations + model invariants.

**Deliverables**
- `User` with `first signup = admin` rule enforced in `before_create`
- Encrypted user credentials: `claude_api_key`, `github_token` (Rails 7+
  `encrypts :attr` with deterministic=false)
- `Repository`: `owner/name`, `default_branch`, `polling_enabled`,
  `trigger_label` (default `syrus`), `belongs_to :user`
- `Job` with state machine: `queued → running → succeeded | failed | cancelled`,
  `belongs_to :repository`, `belongs_to :user`, has `issue_number`,
  `branch_name`, `pr_number`, `started_at`, `finished_at`
- `JobLog` with `belongs_to :job`, append-only transcript chunks
- Invitation model so admin can invite users (lightweight, like tiny_ci)
- Specs cover the state machine + first-admin rule

**Out of scope:** Polling, worker, UI.

---

## M2 — GitHub poller

Periodic Solid Queue job ingests issues from registered repos and queues `Job`s.

**Deliverables**
- `PollRepositoryJob`: per-repo, runs every N minutes via Solid Queue's
  recurring tasks (`config/recurring.yml`)
- Uses the *repo owner's* `github_token` (per-user, never global)
- Triggers on a label (default `syrus`) being applied to an issue
- Dedup: don't enqueue if a non-terminal `Job` already exists for that issue
- `IngestPolicy` handles "ignore PRs", "ignore closed issues", "respect
  `syrus-skip` opt-out label"
- Octokit-backed; one `GithubClient` wrapper per user with rate-limit handling
- Specs use VCR cassettes against fixed Octokit responses

**Out of scope:** Actually running the harness — just enqueue `Job` records.

---

## M3 — Deterministic harness (no AI)

**This is the make-or-break milestone.** A `Job` runs end-to-end and opens an
empty PR with zero AI involvement. If this layer is flaky, M4 is hopeless.

**Deliverables**
- `RunJob` Solid Queue worker (separate container in M7; same process for now)
- Acquires a `git worktree` under `tmp/worktrees/{job_id}/`
- Creates branch `syrus/issue-{N}-{slug}` from `default_branch`
- Makes a placeholder commit (e.g., touches `.syrus-marker` with the job id)
- Pushes branch via per-user GH token, opens PR with templated title/body
  referencing the issue
- Persists transcript chunks to `JobLog` as it goes
- On success/failure: cleans up worktree, transitions state, records artifacts
- Cancellation path: SIGTERM-aware, marks `cancelled`, cleans up
- Concurrency: at most one running `Job` per repo at a time
- Integration test: register a real fixture repo, run end-to-end, assert PR opens

**Out of scope:** Anything AI. The PR has a one-line marker commit. That's the
whole point — proves the plumbing.

---

## M4 — Agent invocation

Replace the placeholder commit with a real `claude-code` run.

**Deliverables**
- `AgentInvocation` service class: shells `claude-code` with the issue body
  as the prompt, in the worktree, with the user's `claude_api_key`
- Streams stdout chunks into `JobLog` in near-real-time
- Wall-clock + token budget; abort and mark failed if exceeded
- Capture final `git diff` as the artifact alongside the transcript
- Failure modes covered: empty diff (agent gave up), syntax error in
  generated code, agent infinite loop
- Spec: a stubbed `claude-code` returns a deterministic patch; assert the
  patch lands as a commit and the PR is opened

**Out of scope:** UI, multi-turn conversations, PR feedback.

---

## M5 — Web UI

Operator surface. Tailwind + Hotwire/Turbo, no React.

**Deliverables**
- Login + invite flow (devise/rodauth)
- Credentials page: paste GH token + Claude API key (write-only inputs,
  never echo back)
- Repository registry: add/remove, toggle polling, set trigger label
- Dashboard: recent jobs across all repos, status badges
- Job detail: live-streaming transcript via Turbo Streams, diff view,
  link to PR
- Replay button: enqueues a new `Job` with the same issue
- Cancel button: signals the worker

**Out of scope:** Admin moderation, audit log, search.

---

## M6 — PR feedback loop

When a reviewer asks for changes on a syrus-opened PR, dispatch a follow-up.

**Deliverables**
- `PollReviewCommentsJob`: per-PR, every N minutes
- Detects new review comments / change requests posted *after* the last
  syrus commit
- Dispatches a `FollowUpJob` carrying the comment text + diff context
- Agent receives the comment as additional instruction, commits to the
  same branch
- "Done" signal: a label like `syrus-stop` on the PR halts polling

**Out of scope:** Multi-step conversations within a single comment, image
attachments.

---

## M7 — Hardening

Production readiness. No new features.

**Deliverables**
- Worker isolated to its own k8s Deployment (separate from web pod)
- Resource limits (cpu/memory) tuned from observed usage
- Secrets: encrypted creds backed by k8s Secret + Rails master key, not
  plaintext in MySQL dump
- Prometheus metrics: jobs queued / running / completed / failed by repo,
  agent latency histograms, GH rate-limit gauges
- Structured JSON logs, correlation id per job
- Retention: archive `JobLog` blobs older than N days to S3/MinIO, keep
  metadata
- Sentry-equivalent error reporting

**Out of scope:** SSO, audit log UI.

---

## M8 — Rollout

Real users on real repos.

**Deliverables**
- `green_acres/apps/syrus.py` deploying web + worker to K3s
- Traefik route at `agents.green-acres.estate` (or chosen domain)
- MySQL via timescaledb-style dedicated instance, backed up to MinIO
- First production repo (likely `green_acres` itself) registered and
  running
- Per-repo claude skills (`process-issues`, `process-prs`,
  `implement-issue`) deprecated and removed once migration is stable
- Runbook: how to register a repo, how to debug a stuck job

**Out of scope:** Multi-tenancy beyond the household, billing, quotas.

---

## Future ideas

Unscheduled directions. Not committed, not ordered — captured here so they
don't get lost.

### Sandbox the agent in a Docker container

Phase A (`~/.syrus/worktrees/{run_id}`, outside Rails.root) stops the
*accident* class of agent-leaks-into-the-operator's-checkout. The
*determined* class needs real isolation: each Run executes inside a
disposable Docker container with only its worktree bind-mounted, the
host filesystem otherwise invisible, and process limits applied. Same
posture we'll need for M8's k8s deployment — building it now is
production-parity, not premature. Tracked in #29.

### Non-GitHub task sources

Ingest work from todo lists and task trackers beyond GitHub Issues — Jira,
Asana, Linear, plain Markdown TODO files, etc. Each source becomes another
poller feeding the same `Job` pipeline; the harness shouldn't care where the
prompt came from.

### Auto-react to broken-build signals

Watch GitHub for failure signals (red CI, failing checks, new bug reports
matching a pattern) and dispatch a fix `Job` automatically. A self-healing
mode for repos that opt in. Needs careful gating to avoid noisy flapping
PRs.

### Quality graders before PR submission

A `Job` only opens its PR once a configurable set of *graders* all pass.
Graders are pluggable quality signals; if any fails, the agent receives
the failure context and iterates rather than shipping a red PR. Examples:

- **CI graders** — delegate test/build execution to an external CI system
  (TinyCI et al) instead of running tests inside the worker. Keeps the
  worker pod lean and reuses existing build infra.
- **Adversarial review graders** — another agent reviews the diff with a
  critical prompt ("find bugs", "challenge this design") and votes
  approve/reject with rationale.
- **Static graders** — linters, type checkers, security scanners,
  coverage thresholds.
- **Custom graders** — arbitrary user-defined scripts or LLM prompts
  scoped per repo.

Per-repo config picks which graders are required vs advisory.

### Multi-layer rate limiting

The single "one running `Job` per repo" rule from M3 isn't enough.
Production needs several limits stacked together:

- **Concurrency caps** — max parallel `Job`s globally, per-account, and
  per-repo. Enforced at dispatch time; excess jobs queue rather than run.
- **Time spacing** — minimum gap between consecutive `Job`s on the same
  repo (and same account), so a flood of new issues doesn't unleash a
  swarm at once. Token-bucket or fixed-window, configurable per scope.
- **Burst vs sustained** — short-term bursts allowed up to a cap, but
  sustained rate clamped lower to stay under GitHub / Claude API limits.

Every limit needs to be visible in the UI (current usage vs cap) and
overridable per repo for trusted setups.

### Task dependency modeling

Let a `Job` declare it depends on other jobs (or external work). Visualize
the resulting graph as a Gantt chart and a dependency graph in the UI.
Useful when one issue blocks another or when a multi-step plan is split
across PRs.

### Agent log storage + UI

Persist full agent transcripts (not just streamed chunks) and surface them
in the web UI — searchable, linkable, diff-able across runs. Overlaps with
`JobLog` from M1/M5 but goes further: structured tool-call timelines,
token/latency breakdowns, replayable sessions.

### REST API

Expose the core resources (`Repository`, `Job`, `JobLog`) over a versioned
REST API so external tools and scripts can register repos, enqueue jobs,
and stream logs without going through the web UI.

### MCP API

Speak the Model Context Protocol so other agents can use Syrus as a tool —
list repos, enqueue a job on an issue, fetch job status and logs. Turns
Syrus into a building block for higher-level agent workflows.

### Syrus CLI

Command-line tool wrapping the REST/MCP API so a developer (or an agent
running locally) can drive Syrus from the terminal: `syrus jobs list`,
`syrus run <repo> <issue>`, `syrus logs --follow <job>`. Useful for ops
and for agents that prefer a CLI surface to an HTTP one.

### Live read-only job view

While a `Job` is running, users get a read-only view of its in-flight
state: chat log streaming as the agent talks, current diff, tool calls
as they happen. Extends the M5 transcript view with richer real-time
detail. No interaction — just observability.

### Repo browsing view

Browse the working tree of a repo at a given point in time, including the
post-run state of any `Job` (the worktree as it was when the PR opened).
Lets users inspect what the agent actually produced beyond the diff —
helpful when reviewing large or generated changes.

### Auto rebase-and-merge on approval

Watch the review signal as another input alongside review comments (M6).
When a syrus-opened PR receives an approving review and all required
checks/graders are green, automatically rebase the branch onto its base
and merge — no human button-press needed. Per-repo opt-in, with a kill
switch label (e.g. `syrus-no-automerge`) for cases the reviewer wants
to merge by hand.

### Auto-rebase stale PRs

When a syrus-opened PR's branch falls behind its base and would no longer
apply cleanly (or has lost its merge-clean status), automatically rebase
it onto the latest base and push. If the rebase hits conflicts the agent
can't resolve mechanically, dispatch a follow-up `Job` with the conflict
context so the agent can fix it. Keeps long-lived PRs mergeable without
manual intervention.

### Properly formatted diff view

Render the agent's `git diff` in the job UI as a real diff — syntax
highlighting, side-by-side or unified toggle, expand/collapse per file,
line numbers, copy-line. Today's "DIFF" panel is a raw monospace dump;
this turns it into something a reviewer actually wants to read before
clicking through to GitHub.

### Agent ↔ Syrus MCP sidecar

The agent needs a way to communicate structured signals back to Syrus
beyond just the diff: "I can't implement this", "this is already done in
commit X", "here's the PR title and body I want", "please ask the user
to clarify Y". Don't parse trailing JSON from the transcript — that's
one-shot, brittle, and dies with the run. Use MCP instead: the agent
already speaks tool-use natively.

**Shape**: a stdio-mode MCP server spawned by the worker as a sidecar to
`claude-code`. Agent talks to the sidecar over stdio; sidecar talks to
ActiveRecord directly in-process. No network, no auth, no token
lifecycle. The sidecar holds the current `run_id` so the agent can only
act on its own run.

**Initial tool surface** (run-scoped):

- `comment(body)` — append a comment to the run, visible in the UI
  alongside the transcript
- `mark_failed(category, reason)` — categories: `cant_implement`,
  `already_done`, `needs_clarification`, `blocked_external`
- `submit_summary(pr_title:, pr_body:, summary:)` — the agent-authored
  PR copy (single source for it; no JSON-blob fallback)
- `set_progress(stage, note)` — optional mid-run telemetry

**Degradation hierarchy** for the PR-copy case specifically:

1. Agent called `submit_summary` during the main run (cheapest — no
   extra tokens, signal is volunteered)
2. `PrSummarizer` second-shot invocation: a fresh `max_turns: 1` claude
   call rooted in a tmpdir, given the issue + the produced diff, asked
   for `{title, body}`. Catches the "agent forgot to call the tool"
   case without needing a parallel transcript-parsing channel
3. Templated PR body as a last resort, with "no agent summary"
   surfaced in the UI

For non-PR-copy signals (`comment`, `mark_failed`, etc.) there is no
fallback — if the tool wasn't called, the signal didn't happen.

**Audit**: every tool call lands in `JobLog` automatically.

**Reuse**: when the public REST API and MCP API entries below ship,
they expose the same internal services this sidecar uses.

### Unified job page context

Surface *all* relevant context for a job on its detail page, not just
the transcript and diff: the source issue title + body, every issue
comment, the PR title + body, every PR/review comment, plus key
metadata (reviewers, labels, checks). One screen captures the full
state of the conversation around this job — no tab-switching to
GitHub to figure out what's going on.

### In-Syrus comments that trigger re-runs

Let the user comment on a job inside Syrus itself, alongside the
issue/PR comments mirrored from GitHub. By default a new in-Syrus
comment triggers a re-run with the comment appended to the prompt
(opt-out per repo, or per-comment via a "don't re-run" toggle).
Bypasses the heavy GitHub-issue/PR comment workflow when the user
just wants to give a quick instruction — same effect as commenting on
the PR, without the round-trip through GitHub's UI.

### Multiple PRs per issue

Treat one GitHub issue as a collection of attempts, not a single PR.
Replays, parallel variants ("show me three approaches"), and natural
splits (foundation refactor first, then the feature) all want >1
thread on the same issue. M2's dedup already only blocks *non-terminal*
duplicates, so this is mostly a first-class UI/data-model surfacing
job: list every `Job` (thread) attached to an issue, link them
together, and let the user pick a "primary" if useful. The opposite —
one PR closing multiple issues — is *not* modeled structurally;
honor GitHub's `Closes #X, #Y` in agent-authored PR bodies and surface
"also closes #Y" as a read-only link on the job page.

### In-UI agent chat

Optional chat window in the web UI where the user can talk to an agent
that controls Syrus on their behalf — "rerun the last job on issue 42
with extra context", "cancel everything on the foo repo", "show me jobs
that failed this week". A conversational front-end to the same actions
the REST/MCP/CLI surfaces expose.
