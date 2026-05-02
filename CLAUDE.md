# Syrus — agent guide

A multi-user, cross-repo issue→PR automation harness. Owns the
deterministic plumbing (worktrees, branches, PRs, cleanup) so the
agent can focus on writing code. See `README.md` for the human pitch
and `ROADMAP.md` for milestone planning.

## Stack

Rails 8.1.3 · Ruby 3.2.3 · SQLite (dev/test) / MySQL (prod) ·
Solid Queue + Solid Cache + Solid Cable · Tailwind via
`tailwindcss-rails` · Turbo Streams + Stimulus · Octokit for GitHub.

## Architecture in 60 seconds

External polling drives everything — no webhooks. `PollAllRepositoriesJob`
fans out to one `PollRepositoryJob` per active repository, which lists
issues with the configured trigger label. Each new labeled issue creates
a `Job` (the *thread*), which auto-creates an initial `Run` (the *attempt*),
which auto-enqueues a `RunJob`. `PollAllPullRequestsJob` does the same
for PR review feedback, creating follow-up `Run`s on existing `Job`s.

The two state machines (AASM):

```
Job (one per issue):    open ⇄ closed
Run (one per attempt):  queued → running → succeeded | failed | cancelled
```

`Job` carries the GitHub identifiers (issue + PR numbers, branch name).
`Run` carries the per-attempt state — prompt, agent metadata, diff,
PR copy submitted by the agent.

### Per-Run pipeline (`app/jobs/run_job.rb`)

1. **`JobWorkspace`** lazy-clones the repo into a shared bare cache at
   `$SYRUS_DATA_ROOT/clones/<repo_id>`, then carves a `git worktree` at
   `$SYRUS_DATA_ROOT/worktrees/<run_id>` on a fresh `syrus/issue-<N>-<job_id>`
   branch (initial run) or the existing branch (follow-ups). Cleaned up
   in `ensure`.
2. **`AgentInvocation`** spawns `claude --print` in the worktree. Streams
   `stream-json` events through `process_event`, captures `final_text`
   and metadata from the `result` event. Pluggable `runner:` for tests.
3. **MCP sidecar** — `bin/syrus-mcp-sidecar`, spawned by `claude` over
   stdio via a per-run `mcp.json` tempfile RunJob writes. Exposes one
   tool, `submit_summary(pr_title, pr_body, summary)`, which writes
   directly onto the `Run` and appends a `JobLog` audit line. See
   `app/services/syrus_mcp/`.
4. **PR copy degradation** — `open_pull_request_if_missing` reads the
   agent's submitted title/body first; falls through to `PrSummarizer`
   (a single-shot `claude` call against the diff); falls through to a
   templated default. Path 2 and 3 are last-resort safety nets — path 1
   is the goal.
5. **Diff capture** uses `git diff main...HEAD` (three-dot — what
   GitHub's "Files changed" tab shows) to avoid pollution when main
   moves forward while the syrus branch is open.

### Live UI

`Job` and `Run` use `broadcasts_refreshes` + Turbo morph (`<%= turbo_refreshes_with method: :morph %>`)
so the worker's DB writes update the operator's browser without a refresh.
Dev mode uses `solid_cable` (NOT `async`) so cross-process broadcasts work.
The transcript element on the show page uses `data-turbo-permanent` to
preserve scroll position across morphs.

## Conventions

- **Prompts** all live under `app/services/prompts/` as PORO classes
  (`Prompts::Initial`, `Prompts::PrFeedback`, `Prompts::PullRequestSummary`,
  `Prompts::SubmitSummaryInstructions`). Each has a `to_s`. Compose by
  appending; never inline prompt text in jobs/services.
- **Encrypted attributes** — `User#github_token`, `User#claude_oauth_token`
  use Active Record Encryption. Means `RAILS_MASTER_KEY` is required in
  any process that touches them. Smoke tests inside containers without
  the key will fail at User creation — by design.
- **AASM events on Run** — call `start!`, `succeed!`, `fail!`, `cancel!`,
  always followed by `save!` (callbacks set timestamps but don't persist).
  See `Run` model.
- **Per-repo concurrency** — `RunJob` uses Solid Queue's `limits_concurrency`
  keyed on `repository_id` so two runs on the same repo never overlap.
- **Three-dot diffs only** — `git diff <base>...HEAD`, never two-dot.
  Lesson learned the hard way (commit `67b2bf9`).
- **Worktrees live outside the repo** — under `$SYRUS_DATA_ROOT` (default
  `~/.syrus`). The agent's `chdir` MUST NOT be inside the operator's
  checkout. (Lesson from commit `ced3a65`.)
- **Tests** — RSpec, no FactoryBot. Lightweight `Factories` module in
  `spec/support/`. WebMock + VCR for GitHub. The agent runner is stubbed
  via `RunJob.agent_runner` and `PrSummarizer.runner` test seams; never
  shell out to real `claude` from tests.

## Workflows

Local dev:

```
bin/setup          # initial install + DB
bin/dev            # foreman: web + worker + tailwind:watch
bin/rspec          # full suite (~10s, 230+ examples)
bin/rspec spec/jobs/run_job_spec.rb   # one file
```

Docker (production image):

```
docker build --platform linux/amd64 -t syrus:amd64 .
```

The image is single-purpose (worker pod overrides CMD to `["./bin/jobs"]`);
web pod uses the default `./bin/thrust ./bin/rails server`. See
"Deploy target" below for the amd64 / Apple Silicon gotcha.

## Deploy target

K3s on the homelab cluster (Intel NUC 12 → **linux/amd64**). Build
images with `--platform linux/amd64`. On Apple Silicon, use Colima
with Rosetta and the `colima` (docker driver) buildx builder — NOT
the `multi` (docker-container) builder, which falls back to QEMU TCG
and turns 5-min builds into 15-min builds. The full Colima/Rosetta
playbook is in `~/code/greenacres/.claude/skills/colima-amd64-build/SKILL.md`.

Required runtime env:

- `RAILS_MASTER_KEY` — credentials decryption
- `SECRET_KEY_BASE` — sessions, signed cookies
- `DB_HOST`, `SYRUS_DATABASE_PASSWORD` — primary MySQL
- `SYRUS_DATA_ROOT` — defaults to `/home/rails/.syrus`. Mount a PVC
  here on worker pods so the bare-clone cache survives restarts.
  Web pods don't need this volume.

## Things that bit us (don't repeat)

- **`claude --mcp-config` is variadic.** It consumes positional args
  until the next flag, so it MUST be slotted between two flags — never
  immediately before the prompt. (Commit `d9d094e`.)
- **`broadcasts_refreshes_to ->(run) { run.job }`** breaks under
  Action Cable's `async` adapter in dev (single-process). Use
  `solid_cable` in dev (`config/cable.yml`).
- **`db:prepare` errors loudly** when only the primary DB is reachable
  — it tries cache/queue/cable too. The primary still migrates fine.
  Inside containers without all four MySQLs, `|| true` past the error.
- **`BUNDLE_WITHOUT="development"` doesn't exclude `:test`** — use
  `"development:test"` (colon-separated). The Rails 8 default is wrong.
  (Fixed in commit `77cae32`.)

## Key files at a glance

```
app/jobs/run_job.rb                          # the orchestrator
app/services/agent_invocation.rb             # claude subprocess + stream-json parser
app/services/job_workspace.rb                # worktree lifecycle
app/services/git_runner.rb                   # streaming git wrapper
app/services/syrus_mcp/sidecar.rb            # MCP::Server boot + SIGTERM trap
app/services/syrus_mcp/submit_summary_tool.rb # the one MCP tool
app/services/prompts/                        # all agent prompts (PORO)
app/services/pr_summarizer.rb                # second-shot fallback
app/jobs/poll_*.rb                           # 4 polling jobs (cron-style)
app/models/{job,run,repository,user}.rb      # core models + AASM
bin/syrus-mcp-sidecar                        # Ruby binstub, claude spawns this
bin/jobs                                     # Solid Queue worker entry
config/database.yml                          # 4-DB prod (primary/cache/queue/cable)
ROADMAP.md                                   # milestone plan + future work
```
