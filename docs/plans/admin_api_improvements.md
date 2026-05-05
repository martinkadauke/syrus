# Admin API improvements

A running list of cases where the agent (or operator) tried to investigate
something via `/api/v1/admin/*` and hit a wall — either the data wasn't
exposed, the filter didn't exist, or the endpoint outright errored.
Each entry: the investigation that triggered it, what blocked, what to
add. Build incrementally as the painful spots show up; not a big
single-PR effort.

## Open

### Resilience: serializer must tolerate post-success-pruned ClaudeSession

**Triggered**: `GET /api/v1/admin/jobs/80` returned 500
(`NoMethodError: undefined method 'bytesize' for nil:NilClass` at
`jobs_controller.rb:120`). After commit `804cdf5` ("Drop
ClaudeSession transcript_jsonl immediately on Run success") the
`claude_session.transcript_jsonl` column is nilable on every
succeeded Run. The `serialize_run` block guards the
`run.claude_session && {...}` outer branch but the inner
`transcript_jsonl.bytesize` and `.count("\n")` blow up when the
record exists but its blob is gone.

**Fix**: nil-safe the two stat fields; surface a
`transcript_pruned: true/false` flag instead of pretending size 0.

**Broader principle**: a single bad row should never 500 the whole
nested-Job dump. Wrap each per-Run / per-Workflow serializer in a
rescue that emits an `error_serializing: "..."` field for that
record only, so the operator at least sees the rest of the Job.

### List filters on `/api/v1/admin/jobs` are minimal

Today's filters: `pr_number`, `issue_number`, `repo`, `state`. Things
that have come up more than once and would be nice:

- `?failed_in_last_24h=true` — jobs whose latest workflow ended in
  `failed` recently. Common "what just broke" question.
- `?has_active_workflow=true` — jobs with a queued/running workflow.
- `?user=email-substring` — admin needs to scope investigations to
  one user's work without learning their numeric id.

### No way to fetch a single Workflow's full state directly

`GET /api/v1/admin/jobs/:id` returns ALL workflows on the Job, which
is fine for small jobs but heavy for long-lived ones (job 80 has 17
workflows). Add `GET /api/v1/admin/workflows/:id` returning that
one workflow with its steps + runs nested. Avoids dumping kilobytes
of unrelated history when investigating one specific failure.

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

_Empty for now._
