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
