# Multi-worker operation

Syrus can run more than one worker pod. Per-Job concurrency is enforced with a
DB-backed SolidQueue semaphore (`RunJob` keyed on `job:<id>`), and recurring
pollers/reapers de-duplicate cluster-wide, so most of the system is already
safe across pods. Two things are specific to multi-worker:

## Global agent-concurrency cap

`JOB_CONCURRENCY` caps agent Runs **per pod**, so total agent concurrency scales
with pod count. `AppSetting.max_concurrent_agent_runs` (admin-configurable,
`0` = unlimited) is a **cluster-wide** cap enforced by `RunJob`: if too many
agent (`:runs`-queue) Runs are already executing across all pods, a new one is
deferred and re-enqueued. Landing/merge and main-branch grader Runs are not
counted. See `AppSetting` reference.

## Retry-from-failed-step worker affinity

Each Job keeps at most one on-disk workspace (see the workspace-per-Job change).
On local-disk-per-worker deployments that workspace lives on **one** pod, so a
"Retry from failed step" (`Workflow#reopen`) must resume on that pod.

- When a `RunJob` runs a workflow it records the pod in `workflows.worker_hostname`
  (`SyrusVersion.hostname` — the same value `InstanceVersion` heartbeats).
- Each worker consumes its own per-pod queue `resume-<hostname>` (declared in
  `config/queue.yml`, alongside `runs`).
- On reopen / post-crash re-enqueue, `Run#enqueue_run_job` routes to
  `resume-<hostname>` **only when that pod is still alive**
  (`InstanceVersion.worker_live?`, 2-minute heartbeat window). If the pod is
  gone — deploy, eviction, restart with a new pod name — its local workspace is
  gone too, so routing falls back to the normal `runs` queue and any worker
  re-clones a fresh workspace (a normal "start over").

This needs no configuration: on a single worker it routes reopens back to that
worker; in local/dev (no `InstanceVersion` rows) it degrades to the normal
queue. It becomes load-bearing once you run multiple workers on local disk.

Note: affinity is keyed on the **pod hostname**. A pod restarting on the same
node with a `hostPath` workspace volume gets a new hostname, so a pending reopen
degrades to a fresh clone even though the files are still on the node — correct,
just not optimal. Keying on node name would tighten that later.
