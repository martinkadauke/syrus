# Admin API improvements

A running list of cases where the agent (or operator) tried to investigate
something via `/api/v1/admin/*` and hit a wall — either the data wasn't
exposed, the filter didn't exist, or the endpoint outright errored.
Each entry: the investigation that triggered it, what blocked, what to
add. Build incrementally as the painful spots show up; not a big
single-PR effort.

## Open

### No "bulk" run lookup

When you want runs across a date range / state / trigger_kind without
walking each Job's response, you have to loop by Job id. Add
`GET /api/v1/admin/runs?state=failed&since=...&trigger_kind=...`
that returns compact run rows (id, job_id, state, started/finished,
last error class). Mirrors the queue's `/api/v1/admin/queue/failed`
shape but for the Run domain.

### Sensitive-data clarification

Currently `agent_diff_bytes` is exposed but not the diff itself; the
transcript JSONL is exposed in full via `/runs/:id/transcript/raw`.
That's the right policy for the operator (they wrote the agent's
prompt, they own the output). But document the boundary in this
file as it stabilizes — what we DO redact (the GH token, the
encrypted columns), what we DON'T (transcripts, diffs, prompts).

## Resolved

### `GET /api/v1/admin/workflows/:id` (single-workflow detail)

`GET /api/v1/admin/jobs/:id` returns every Workflow on a Job, which
is heavy for long-lived Jobs (today's Job 80 has 17). The new
endpoint returns one Workflow's nested state (steps + runs +
diagnostics + claude_session metadata) plus a thin Job envelope so
the caller can drill back up. Reuses `Admin::JobStateSerializer`
(extracted from JobsController) — same per-record-resilience.

### List filters on `/api/v1/admin/jobs`

Three new filters: `?failed_in_last_24h=true` (Jobs whose LATEST
workflow ended `failed` within 24h — careful not to re-surface fixed
work), `?has_active_workflow=true` (Jobs with queued/running
workflows), `?user=substring` (User#email_address LIKE matching).
The "latest workflow" filter uses a `ROW_NUMBER() OVER (PARTITION BY
job_id ORDER BY created_at DESC)` window function so a Job that
failed but was successfully retried doesn't show up.

### Serializer resilience for `/api/v1/admin/jobs/:id`

Triggered by `Job 80` returning 500 because `serialize_run` called
`.bytesize` on a transcript that was pruned post-success
(`804cdf5`). Two-part fix:

1. Nil-safe the transcript fields directly + flag pruned bodies via
   `transcript_pruned: true/false` instead of pretending size 0
   (commit `c5e9027`).
2. Wrap each per-record serializer (`serialize`, `serialize_workflow`,
   `serialize_step`, `serialize_run`) in a `rescue => e` that swaps
   in `{ id: ..., error_serializing: "Class: message" }` and logs
   the error. One bad row no longer 500s the whole nested dump.
