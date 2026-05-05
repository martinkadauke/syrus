# Plan: recurring schedule cadences → DB-driven

_Part of the [magic-constants index](magic-constants-INDEX.md). The
most-involved of the four; lower priority but high-value once the
shape settles._

## Context

`config/recurring.yml` hard-codes the cadence of every recurring job:

```yaml
poll_repositories:    every 5 minutes
poll_pull_requests:   every 5 minutes
poll_rebases:         every 5 minutes
poll_scheduled_tasks: every 1 minute
reap_stale_runs:      every 1 minute
prune_claude_sessions:        every day at 3:00am
prune_run_diagnostics:        every day at 3:10am
prune_workflow_workspaces:    every 2 hours
clear_solid_queue_finished_jobs: every hour at minute 12  # production only
```

These are real operational levers. Earlier in the codebase's history
the rebase poll was every 15 minutes; bumping it to 5 minutes was a
config edit + redeploy. With the ETag-conditional-request work
landed, polling every minute is cheap — but flipping that lever
should not require a deploy.

The `every N minutes` cron syntax also bottoms out at 1 minute. If
we want sub-minute polling for any of these (e.g. dispatch the next
runnable Step within seconds of a heartbeat), the recurring.yml
mechanism needs more flexibility anyway.

## Why this is its own plan

Unlike the other three plans, this one isn't a simple
`CONSTANT → AppSetting column` migration. Solid Queue's recurring
schedule loads from `config/recurring.yml` at boot. Switching to a
DB-driven schedule means either:

- (a) Patching Solid Queue to consult an `AppSetting` (or a new
  table) on each scheduling tick, or
- (b) Adding a separate Syrus-managed scheduler that runs on a
  short fixed cadence and decides whether each job is due based on
  per-job DB-stored cadences and last-fired-at watermarks, or
- (c) Generating `config/recurring.yml` from the DB at boot, with a
  manual `kubectl rollout restart` whenever an admin wants to apply
  changes.

(c) is the cheapest path but doesn't deliver the "no redeploy" promise.
(a) is the most invasive (requires a Solid Queue patch). (b) is the
middle ground and what this plan recommends.

## Proposal: a `RecurringJobConfig` model + an in-process tick loop

```sql
CREATE TABLE recurring_job_configs (
  id            BIGINT PRIMARY KEY AUTO_INCREMENT,
  key           VARCHAR(64) UNIQUE NOT NULL,        -- "poll_repositories"
  class_name    VARCHAR(128) NOT NULL,              -- "PollAllRepositoriesJob"
  interval_seconds INTEGER NOT NULL,                -- e.g. 300 for every-5-min
  enabled       BOOLEAN NOT NULL DEFAULT TRUE,
  last_fired_at DATETIME NULL,
  next_fire_at  DATETIME NULL,
  notes         TEXT NULL,                          -- admin-written context
  created_at    DATETIME NOT NULL,
  updated_at    DATETIME NOT NULL
);
```

A new `RecurringTickJob` runs every 30 seconds (a fixed cadence in
`config/recurring.yml` — the only thing that stays in the YAML).
On each tick:

1. Find rows with `enabled = true` and `next_fire_at <= now`.
2. For each, enqueue the corresponding `class_name` and update
   `last_fired_at = now`, `next_fire_at = now + interval_seconds`.

This gives a 30s scheduler resolution — plenty for everything
currently in the YAML. If we ever want sub-30s, drop the tick
cadence.

**Migration of existing schedule:** at first boot after the change,
seed the table from `config/recurring.yml`'s current values so the
existing schedule is preserved. After that, the YAML still has the
`recurring_tick` entry and nothing else.

## Why not just bump cadence in YAML for each change?

Because the user surface ("admin can dial down rebase polling on a
quiet day") needs to work without ssh + kubectl + deploy. The whole
point of this work is to avoid hardcoded operational policy.

Same reason `AppSetting.polling_paused` exists as a DB flag rather
than an env var: incident response speed.

## What this enables

- Admin form per recurring job: enabled toggle, interval slider, a
  notes field for "why I changed this."
- Per-environment cadences without per-environment YAML — staging
  could poll less aggressively than prod.
- Disable-at-runtime for incident response (more granular than the
  existing `polling_paused` global toggle).
- A "fire now" button per recurring job (similar to the existing
  ScheduledTask "fire now"), useful for testing and recovery.

## Constants subsumed

Every cadence in `config/recurring.yml` becomes a row in
`recurring_job_configs`:

| Key | Old cadence | New default `interval_seconds` |
|---|---|---|
| `poll_repositories` | every 5 minutes | 300 |
| `poll_pull_requests` | every 5 minutes | 300 |
| `poll_rebases` | every 5 minutes | 300 |
| `poll_scheduled_tasks` | every minute | 60 |
| `reap_stale_runs` | every minute | 60 |
| `prune_claude_sessions` | every day at 3:00am | 86400 (with phase offset) |
| `prune_run_diagnostics` | every day at 3:10am | 86400 |
| `prune_workflow_workspaces` | every 2 hours | 7200 |
| `clear_solid_queue_finished_jobs` (prod only) | every hour at minute 12 | 3600 |

The "at HH:MM" phase offsets need a small additional column
(`fire_at_minute INTEGER NULL`?) for the daily prunes. Or fold those
into the same row as `last_fired_at` and let the dispatcher figure
out the next clock time. Trade-off:

- **Pure interval**: simpler dispatcher, but daily prunes start
  drifting from "3am exactly" if the worker has any downtime.
  Probably fine — the prunes run idempotently.
- **Cron-string column**: keeps the absolute-time semantics. Adds a
  cron parser dependency. Heavier.

Recommendation: pure interval for v1, accept the drift on daily
prunes. Add cron-string support later if the drift becomes a real
operational problem.

## UI

Admin-only. New section in the settings UI (or its own page,
`/admin/recurring_jobs`). Lists each row with:

- enabled toggle
- interval input (seconds with friendly format hint: "300 = every 5
  minutes")
- last fired (relative time)
- next fire (relative time)
- notes textarea
- "fire now" button

Plus a top-level read-only stat: "next due: <key> in <relative
seconds>".

## Migration approach (rollout)

1. **Schema + model**: add the table, the model, the seed data.
   No behavior change yet (the YAML still drives the actual schedule).
2. **Tick job**: add `RecurringTickJob`, register it in `recurring.yml`
   at every-30-seconds. Initially the tick job is a no-op (or just
   logs what it WOULD fire) so we can compare against the
   YAML-driven schedule.
3. **Cutover**: remove the YAML entries (except the tick), now the
   tick job actually enqueues. Watch metrics for 24-48h to confirm
   firing cadence matches the prior schedule.
4. **UI**: admin form lands.
5. **Verify**: after a week of clean operation, drop the YAML for the
   migrated jobs entirely so there's a single source of truth.

Each step reversible by reverting the previous commit.

## Acceptance

- [ ] `recurring_job_configs` table exists with rows seeded from the
      current YAML
- [ ] `RecurringTickJob` runs every 30s and enqueues each due row's
      `class_name`
- [ ] All previously-YAML-driven recurring jobs now fire from the
      DB schedule
- [ ] Admin UI shows the table, lets you toggle / change interval /
      fire-now / disable
- [ ] Spec coverage:
   - tick job dispatches when `next_fire_at <= now`
   - tick job skips disabled rows
   - changing `interval_seconds` updates the next fire time
   - "fire now" enqueues immediately and bumps watermarks
- [ ] After cutover, `config/recurring.yml` contains only
      `recurring_tick`

## Out of scope

- Per-Job-or-per-Repository cadences (e.g. "this big repo polls
  every 15 min, that small one polls every 1 min"). Plausible
  follow-up, but adds complexity to the dispatch logic and schema.
- Per-environment overrides via the DB (staging vs prod): handle
  by keeping each environment's `recurring_job_configs` table
  independently configured.
- Cron-string scheduling beyond pure intervals. Defer until needed.
- Replacing `ScheduledTask` (user-defined cron tasks) — that's a
  different model with its own UI; this plan only owns
  Syrus-internal recurring jobs.

## Cross-references

- The site-wide plan owns the constants this plan doesn't touch
  (e.g. `RUNS_PAUSED_RETRY_DELAY` is set from `AppSetting`, not
  from a recurring job config).
- Roadmap: "Multi-layer rate limiting" — once concurrent-run caps
  are wired in, an admin can simultaneously back off via cadence
  and via concurrency caps for finer control.
