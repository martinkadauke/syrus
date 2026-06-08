# Landing merge-train (Fix 4)

Status: **proposed** — design for review, not yet implemented.

## Why

Landing is strictly serialized per repository: only one Job per repo is
`landing` at a time (`LandingQueueProcessor#landing_in_progress_for_repository?`).
When many approved PRs share one base branch (an Epic batch), every merge
moves the base and re-dirties all the others. The cost is roughly
**O(N²)** in rebases and grader runs.

Production evidence (24h, before the incremental fixes below):

| Metric | Count |
|---|---|
| PRs merged | 14 |
| auto_merge workflows cancelled/deferred | 16 (13 on `unknown`) |
| Grader runs on auto_merge workflows | 236 (~17 per merge) |
| Rebase workflows | 58 + 3 failed (~4 per merge) |

One Job (804) sat in `landing` for ~41h.

### Incremental fixes already shipped (the baseline this builds on)

1. **Wait out transient mergeability** (`Steps::AutoMerge`) — poll for a
   post-push `unknown` to settle before deferring, instead of discarding
   a green grade. Removes the dominant cancellation cause.
2. **Front-of-queue rebasing only** (`PollMergeStateJob` +
   `LandingQueueProcessor.rebase_prefetch_candidate?`) — stop rebasing
   the whole approved backlog every poll; only the front
   `REBASE_PREFETCH_DEPTH` Jobs.
3. **Opt-in `trust_clean_rebase_grade`** (`Steps::ForcePush` +
   `LandingValidationCache`) — carry a green grade across a clean rebase
   so the next attempt skips re-grading.

These cut the wasted work dramatically but do **not** raise the
throughput ceiling: PRs still land one-at-a-time, each rebased onto the
previous merge and graded once. For a 30-PR batch that's still 30
sequential (rebase + grade + merge) cycles. The merge-train removes that
ceiling.

## Goal / non-goals

**Goal:** land a batch of N approved, same-base PRs in far fewer than N
sequential grade cycles, while preserving the safety guarantee that what
lands on the base is graded green *as it will exist after merge*.

**Non-goals:**
- Cross-repo changes (landing is already parallel across repos).
- Changing the approval model, dependency/Epic gating, or the rebase
  conflict-resolution chain.
- Removing the per-PR final gate's *correctness* (only its redundant
  repetition).

## Options

### Option A — GitHub native merge queue

Enable GitHub's merge queue on the repo; Syrus enqueues approved PRs and
lets GitHub build the speculative merge group, run required checks once
per group, and merge in order.

- **Pros:** GitHub owns batching, speculation, and bisection on failure;
  no Syrus-side train state machine.
- **Cons:** requires required status checks configured on GitHub (Syrus
  graders are local, not GitHub checks — a significant integration: we'd
  have to publish grader results as commit statuses/checks); branch
  protection + merge-queue config per repo; weaker fit with Syrus's
  polling-only, no-inbound-callback architecture (merge queue is
  event-driven); less control over the agent `landing_fix` repair loop.
- **Verdict:** strong for repos already living in GitHub-checks land;
  poor fit for Syrus's local-grader, poll-driven model today. Revisit if
  we ever publish graders as GitHub checks.

### Option B — Syrus-internal merge train (recommended)

Syrus builds a *train*: take the first K eligible same-base approved Jobs
in queue order, rebase them into a single speculative integration branch
(stacked, in order), run graders **once** on the train tip, and if green,
fast-forward/merge each PR in order. On failure, bisect: split the train
and re-run, ejecting the offending PR.

- **Pros:** reuses existing graders, rebase chain, and workspace model;
  stays poll-driven; one grade per train instead of one per PR; keeps the
  `landing_fix` repair loop available at the train level.
- **Cons:** Syrus owns the train state machine, speculation, and failure
  bisection — real complexity. Must interact correctly with
  dependencies, Epics, and stacks.

The rest of this doc designs Option B.

## Design (Option B)

### Concept

A **MergeTrain** is an ordered set of approved Jobs for one
(repository, base_branch) that Syrus attempts to land together:

1. **Assemble** — pick the first K eligible Jobs in
   `LandingQueueProcessor` order for the repo/base that are mergeable or
   cleanly rebaseable, share the same base, and have no cross-train
   dependency ordering violations. K = `AppSetting.merge_train_max_size`
   (start small, e.g. 5).
2. **Build** — create an integration branch
   `syrus/merge-train-<id>` at the base tip; rebase each member's branch
   onto it in order (reusing `AutoRebase`/agent rebase for conflicts).
   A member that conflicts irreparably is **ejected** (stays approved,
   re-queued for a later train) and the build continues without it.
3. **Grade** — run the configured graders **once** on the integration
   tip (the state that will exist after all members merge). Reuse
   `grader_fanout`/`grader_collect`. On failure, run `landing_fix` once
   at the train level, re-grade.
4. **Land** — if green, merge each member PR in order. Because each was
   rebased into the integration branch and the tip is graded, each merge
   is a fast-forward of already-graded content. Update each Job to
   `closed/pr_merged`.
5. **On grade failure that repair can't fix** — **bisect**: split the
   train in half, grade each half, recurse to isolate the offending
   member; eject it (fail its landing so an operator/agent handles it)
   and land the rest.

### New trigger kind / workflow

`Workflow#trigger_kind = "merge_train"`, queue `:merges`. Steps:

```
merge_train_assemble -> merge_train_build ->
  retry_until(grader_fanout -> grader_collect, repair: landing_fix) ->
  merge_train_land
```

- `merge_train_assemble` (non-agentic) — select members, lock the repo
  landing slot, persist the member list + order.
- `merge_train_build` (non-agentic, may dispatch agent rebases) — build
  the integration branch; eject conflicting members.
- graders — reuse existing steps, run against the integration branch in
  the train's `WorkflowWorkspace`.
- `landing_fix` — reuse; repairs apply to the integration branch and are
  force-pushed to each member as needed (or the train re-derives member
  branches from the integration result).
- `merge_train_land` (non-agentic) — merge members in order; on partial
  failure, defer the unmerged remainder back to `approved`.

### Data model

`merge_trains` table: `id, repository_id, base_branch, state
(building|grading|landing|succeeded|failed|cancelled), integration_branch,
integration_sha, created_at, finished_at`.

`merge_train_members`: `merge_train_id, job_id, position, state
(included|ejected|merged|failed), reason`.

Jobs gain no new state — members move through the normal
`landing → closed/pr_merged` (success) or back to `approved` (ejected /
remainder). `Job` already serializes via the per-repo landing guard; the
train *is* the single landing occupant for the repo while it runs.

### Control flow / integration with LandingQueueProcessor

- `LandingQueueProcessor#call` gains a branch: when a repo has ≥
  `merge_train_min_size` eligible same-base approved Jobs and
  `AppSetting.merge_train_enabled?`, dispatch a `MergeTrain` workflow
  instead of a single `AutoMerge`. Below the threshold, keep today's
  single-Job `AutoMerge` path (no behavior change for small/idle repos).
- The train holds the repo's landing slot (`Job.landing` for all members)
  so the recurring loop won't double-dispatch.
- Dependencies / Epics / stacks: members must respect
  `landing_queue_prerequisite_ids`. Simplest v1: only assemble members
  with **no unmet intra-batch dependencies**; a member whose prerequisite
  isn't already merged or earlier in the same train is excluded. Stacks
  (`parent_job_id`) are included only as contiguous, correctly-ordered
  runs or excluded from the train (fall back to `stack_rebase`).

### Safety

The core guarantee is preserved: graders run on the **exact integrated
tree** that will exist on the base after the members merge, and members
merge as fast-forwards of that graded content. This is *stronger* than
today's per-PR grade-against-its-own-base, because it grades the actual
combined result. `trust_clean_rebase_grade` becomes unnecessary inside a
train (the train always grades the integrated tip once).

Failure isolation via bisection ensures one bad PR doesn't block the
batch: it's ejected and the rest land.

### Rollout

- `AppSetting.merge_train_enabled` (default **off**),
  `merge_train_min_size` (e.g. 4), `merge_train_max_size` (e.g. 8).
- Ship dark; enable for `tkadauke/raytracer` first (the batch repo).
- Metrics to watch: merges/hour, grader runs per merge, ejections per
  train, train build failures.

### Testing

- Assemble: ordering, dependency/Epic/stack exclusion, size bounds.
- Build: clean rebases, conflict ejection, base-moved-mid-build.
- Grade + bisection: injected failing member isolates correctly.
- Land: partial-merge failure defers the remainder; per-repo serialization
  holds.
- All via existing seams (`RunJob.agent_runner`, stubbed graders, WebMock
  for Octokit). No real `claude`/GitHub.

## Estimate

Medium-large: ~2 models + migration, 1 workflow + 3 step handlers,
LandingQueueProcessor branch, AppSettings, and a focused spec suite.
Recommend landing it behind the disabled flag, then enabling per-repo.

## Decision needed

1. Option A (GitHub merge queue) vs **B (internal train)** — this doc
   recommends B for fit with Syrus today.
2. v1 scope: include stacks/Epics in trains, or exclude them initially
   (recommended: exclude, fall back to current path)?
