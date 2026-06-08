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

**Goal:** land an **Epic's** children in far fewer than N sequential grade
cycles, while (a) preserving the safety guarantee that what lands on the
base is graded green *as it will exist after merge*, and (b) guaranteeing
**Epic consistency** — an Epic advances as a whole, green, dependency-closed
set or not at all, never as a half-merged state on `main`.

**Non-goals:**
- Cross-repo changes (landing is already parallel across repos).
- Changing the approval model, dependency/Epic gating, or the rebase
  conflict-resolution chain.
- Removing the final gate's *correctness* (only its redundant repetition).
- Batching loose, non-Epic PRs in v1 (kept on the existing per-Job path).

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

### Option B — Syrus-internal merge train, scoped per Epic (recommended)

Syrus builds a *train* from one Epic's child Jobs: topologically sort the
Epic's ready children, rebase them in order into a single integration
branch, run graders **once** on the integration tip, and if green, land
the whole integration branch into the base in a **single atomic merge**.
If red, bisect over the topological order to isolate the culprit.

The defining property is **Epic consistency**: an Epic advances as a
whole, green, dependency-closed set, or it does not advance at all. There
are never half-merged Epics on `main` — no state where child 3 has landed
but child 5 (which child 7 depends on) is still open or failing.

- **Pros:** one grade per Epic attempt instead of one per child; atomic
  landing eliminates partial-Epic states; the Epic is the *natural*
  batching unit (shared base, shared intent, already dependency-linked);
  topological order is already computed (`dependency_order`); reuses
  graders, rebase chain, workspace, and `landing_fix`. Stays poll-driven.
- **Cons:** Syrus owns the train state machine, speculation, and bisection.
  Atomic landing of the integration branch means child PRs show **Closed**
  rather than **Merged** on GitHub (see "Atomicity vs. PR status").

The rest of this doc designs Option B.

## Design (Option B — per-Epic)

### Trigger

A merge-train attempt is dispatched for an **Epic** (not a loose set of
PRs) when, for that Epic's children on one repository/base:

- `AppSetting.merge_train_enabled?` and the repo opts in, and
- the **readiness policy** is met (see below).

Non-Epic Jobs keep today's single-Job `AutoMerge` path unchanged — the
train is purely additive and Epic-scoped, which keeps the blast radius
small.

**Readiness policy** (`AppSetting.merge_train_readiness`):

- `whole_epic` (default, the strong reading of "no half-merged Epics"):
  dispatch only when **every** open child of the Epic is `approved` (or
  already merged). The Epic then lands all-or-nothing. Maximizes
  consistency; trades latency (waits for the slowest child).
- `green_prefix` (throughput fallback): dispatch when the largest
  dependency-closed prefix of approved children is non-empty; land that
  prefix atomically, leave the rest for a later train. Still never leaves
  a dangling dependent (a prefix is dependency-closed), but the Epic can
  be partially on `main` between trains.

### Steps

`Workflow#trigger_kind = "merge_train"`, queue `:merges`. Belongs to the
Epic (not a single Job); occupies the repo landing slot for the duration.

```
merge_train_assemble -> merge_train_build ->
  retry_until(grader_fanout -> grader_collect, repair: landing_fix) ->
  merge_train_land
```

1. **`merge_train_assemble`** (non-agentic) — gather the Epic's eligible
   children, **topologically sort** them via the existing
   `LandingQueueProcessor#dependency_order` scoped to the Epic, lock the
   repo landing slot (transition members to `landing`), persist the
   ordered member list.
2. **`merge_train_build`** (non-agentic, may dispatch agent rebases) —
   create integration branch `syrus/merge-train-epic-<epic_id>-<n>` at the
   base tip; rebase each member's branch onto the integration tip in
   topological order (reuse `AutoRebase`; on conflict, the agent rebase
   chain). A member that won't rebase cleanly **ejects the Epic attempt**
   under `whole_epic` (you can't skip a child and stay consistent), or is
   deferred-with-dependents under `green_prefix`.
3. **graders** — run **once** on the integration tip (the exact tree that
   will exist on base after the Epic merges). Reuse
   `grader_fanout`/`grader_collect`. On failure, one `landing_fix` repair
   iteration on the integration branch, then re-grade.
4. **`merge_train_land`** (non-agentic) — green → land the integration
   branch into base in a **single merge**, then reconcile child PRs
   (close with a "landed via Epic merge-train" comment linking the merge).
   Mark each child Job `closed/pr_merged`. Close the Epic if all children
   are now merged.

### Bisection (red integration)

Because members are in topological order, every **prefix** is
dependency-closed and independently meaningful. On a grade failure that
`landing_fix` can't repair:

1. Binary-search over prefix length: grade prefix `[0..mid]`.
2. Find the **largest green prefix** `P`.
3. The first member after `P` is the culprit. Under `whole_epic`, **land
   nothing**, eject the culprit (+ its transitive dependents) back to
   per-Job handling (fail landing → operator/agent repairs it), and the
   next train re-attempts the Epic without it. Under `green_prefix`, land
   `P` atomically and defer the rest.

Bisection costs `O(log N)` extra grades **only on failure**; the common
green path is exactly one grade for the whole Epic.

### Atomicity vs. PR status (decision)

Landing the integration branch in one merge means child PR head SHAs are
not ancestors of base (they were rebased), so GitHub marks them
**Closed**, not **Merged**. Options:

- **(recommended) Atomic + close:** one merge of the integration branch
  (via a synthetic Epic integration PR, or by pointing the tip child's PR
  at the integration branch and merging that), then close the other child
  PRs with a back-link. True atomicity; child PRs show "Closed".
- **Per-PR fast-forward in order:** preserves "Merged" badges but is
  **not atomic** — a failure midway leaves a half-merged Epic, defeating
  the goal. Rejected.

### Data model

`merge_trains`: `id, epic_id, repository_id, base_branch, state
(building|grading|landing|succeeded|failed|cancelled), integration_branch,
integration_sha, readiness_policy, created_at, finished_at`.

`merge_train_members`: `merge_train_id, job_id, position, state
(included|ejected|merged|deferred), reason`.

Jobs gain no new AASM state — members ride the normal
`landing → closed/pr_merged` on success or revert to `approved` when
ejected/deferred. The Epic is the unit; the train is its single landing
occupant for the repo.

### Control flow / integration with LandingQueueProcessor

- `LandingQueueProcessor#call` gains an Epic branch: for each repo not
  already occupied, if an Epic meets the readiness policy and the flag is
  on, dispatch a `MergeTrain` for that Epic instead of single-Job
  `AutoMerge`s for its children. Loose (non-Epic) approved Jobs continue
  through the existing per-Job path.
- The existing same-Epic dependency relaxation (a stack inside one Epic
  keeps flowing while the queue serializes merges) composes naturally:
  the train *is* that serialized merge, done once for the whole Epic.
- The train holds the repo landing slot; the recurring loop won't
  double-dispatch.

### Safety

Stronger than per-PR landing: graders run on the **exact integrated tree**
that will exist on base after the Epic merges, and the Epic lands as that
graded tree in one operation. No clean-rebase-trust needed inside a train
(`trust_clean_rebase_grade` is a per-PR optimization for the non-train
path). Bisection guarantees one bad child can't wedge the whole Epic.

### Rollout

- `AppSetting.merge_train_enabled` (default **off**),
  `merge_train_readiness` (`whole_epic` default), `merge_train_max_size`
  (cap members per attempt; very large Epics bisect/land in chunks).
- Ship dark; enable for `tkadauke/raytracer` first (the Epic-batch repo).
- Metrics: merges/hour, grades per Epic landed, ejections per train,
  build failures, time-from-all-approved to Epic-landed.

### Testing

- Assemble: topological order within an Epic; readiness-policy gating;
  size cap.
- Build: clean rebases, conflict handling per policy, base-moved-mid-build.
- Grade + bisection: injected failing child isolates to the right member;
  largest-green-prefix math; dependents of the culprit are held.
- Land: atomic merge closes child PRs + marks Jobs merged + closes Epic;
  `whole_epic` lands nothing on a red attempt; per-repo serialization holds.
- All via existing seams (`RunJob.agent_runner`, stubbed graders, WebMock
  for Octokit). No real `claude`/GitHub.

## Estimate

Medium-large: 2 models + migration, 1 workflow + 3 step handlers, the
LandingQueueProcessor Epic branch, AppSettings, and a focused spec suite.
Land behind the disabled flag, then enable per-repo.

## Decisions needed

1. Option A (GitHub merge queue) vs **B (internal, per-Epic train)** —
   recommends B.
2. Readiness policy default: **`whole_epic`** (strongest "no half-merged
   Epics", higher latency) vs `green_prefix` (lands consistent prefixes
   sooner). Recommends `whole_epic` default, `green_prefix` configurable.
3. Atomicity: accept child PRs showing **Closed** (recommended) to keep
   the merge truly atomic?
4. Loose (non-Epic) Jobs: leave on the per-Job path for v1 (recommended),
   or generalize the train to same-base non-Epic batches later?
