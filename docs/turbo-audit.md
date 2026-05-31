# Turbo audit — current usage, gotchas, defensive defaults

Snapshot of every Turbo touchpoint in Syrus as of the audit. The
goal: stop treating Turbo bugs as one-off mysteries by enumerating
the surface area, documenting the failure modes we've actually hit,
and writing down the defaults that prevent the next round.

## Surface area inventory

### Turbo Frames (`<turbo-frame>`)

Two frame instances in the entire app — Syrus is light on frames.

| Frame | View | Target default | Use |
|---|---|---|---|
| `dashboard_content` | `app/views/home/index.html.erb:41` | `_top` | View toggle (List/Kanban) swaps content in-frame without full nav; everything else escapes |
| `epic_graph_drawer_body` | `app/views/home/index.html.erb:783` | not set (defaults to in-frame) | Drawer body loads via `data-turbo-frame="epic_graph_drawer_body"` link |

**Inbound frame-targeting links** (`data-turbo-frame=` / `data: { turbo_frame: ... }`):

| Target | Where | Count |
|---|---|---|
| `_top` (escape) | Dashboard subject toggle | 3 |
| `dashboard_content` | Dashboard view toggle | 2 |
| `epic_graph_drawer_body` | Epic show-graph menu link | 1 |

### Morph-on-broadcast (`turbo_refreshes_with method: :morph`)

Global, applies to every page. Set once in `app/views/layouts/application.html.erb:15` with
`scroll: :preserve`. Every model that calls `broadcasts_refreshes` triggers a
page-level morph for subscribed pages.

### Turbo Stream subscriptions (`turbo_stream_from`)

| Page | Streams |
|---|---|
| `home/index` (dashboard) | `[user, "jobs"]` |
| `chats/show` legacy fallback | `chat_session_<id>_whiteboard` |
| `jobs/show` | `job`, `[job, "logs"]` |
| `epics/show` | `epic` |

All driven by Action Cable. Adapter is **`solid_cable`** in both dev and prod
(`config/cable.yml`) — the async adapter is intentionally avoided because
worker-process broadcasts wouldn't cross to the browser's WebSocket subscriber.

### Models that broadcast

| Model | Mechanism | Streams to | Notes |
|---|---|---|---|
| `Job` | `broadcasts_refreshes` (self) + `broadcasts_refreshes_to [user,"jobs"]` + `[repo,"jobs"]` | `job` show, dashboard | Refreshes on every save |
| `Run` | `broadcasts_refreshes_to job` + `[user,"jobs"]` | Job show, dashboard | **High traffic** — heartbeat updates trigger morphs on the dashboard. See "Latent risks" below. |
| `Epic` | `broadcasts_refreshes` + `[user,"jobs"]` + `[repo,"jobs"]` | Epic show, dashboard | |
| `RunHealthSnapshot` | `broadcasts_refreshes_to` (lambda) | Targeted | |
| `SpawnedProcess` | `broadcasts_refreshes` | Admin pages | |
| `JobLog` | `broadcasts_to [log.run.job, "logs"]`, `inserts_by: :append` | Job show transcript | **Append**, not morph — different mechanism, no whole-page churn |

### `data-turbo-permanent` (morph-survival islands)

Elements explicitly preserved through morph cycles:

| Element | View | Why |
|---|---|---|
| Live transcript container `run_<id>_logs` | `jobs/_step.html.erb:175` | Holds appended JobLog entries; morph would wipe them between broadcasts |
| Retry-context dialog | `jobs/show.html.erb:126` | In-flight form state survives broadcast morphs |
| Bug-report dialog + button | `shared/_bug_report_button.html.erb` | Same — typed message + screenshot survive |
| Chat manual-proposal dialog | `chats/_manual_proposal_dialog.html.erb` | In-flight form state |
| Chat message input | `chats/_message.html.erb:16` | Preserves user input mid-typing |
| Footer Syrus quote | `layouts/application.html.erb:143` | Cosmetic — stops random quote from re-rolling on every broadcast (was distracting flicker) |
| Repo-issues bulk checkboxes | `repositories/issues.html.erb:165` | Selection survives morph during bulk actions |

### Morph-aware Stimulus controllers

Controllers that listen for `turbo:morph` / `turbo:render` / `turbo:before-morph-element`:

- `chip_bar_controller.js` — re-reads chip tree from `data-chip-bar-tree-value` on morph; uses `turbo:before-morph-element` to protect open popovers from being closed mid-edit
- `bulk_jobs_controller.js` — re-syncs checkbox selection state from sessionStorage on morph

Other Stimulus controllers don't subscribe to morph events. Most are stateless
and fine. The ones holding state without explicit morph-awareness OR
`data-turbo-permanent` are an audit target for future stability.

## Gotchas we've actually hit (and how to avoid recurrence)

### 1. Frame target inheritance: "Content missing"
**Bug:** A `<turbo-frame>` propagates its target to every link inside it unless
overridden. Click a Job link → Turbo fetches `/jobs/123` → looks for the same
frame id in the response → not present → renders the literal text "Content
missing." Cmd-click works because it bypasses Turbo. Hit on the
`dashboard_content` frame (commit `b222bd7`).

**Default:** **Always set `target: "_top"` on a `turbo_frame_tag` unless the
frame's express purpose is to host in-place navigation.** Explicit in-frame
links override the default with their own `data-turbo-frame`. This makes
"escape the frame" the no-thought-needed default; the rare in-frame case is
declared. The View toggle pattern is the model — `data: { turbo_frame:
"dashboard_content", turbo_action: "advance" }` opts into in-frame.

### 2. Page-morph wipes form state (checkboxes, focus, scroll)
**Bug:** A `broadcasts_refreshes` fires while the operator is mid-typing /
mid-selecting / mid-scrolling. Morph re-renders, the input loses focus / the
checkbox unchecks / the scroll jumps. Hit on bulk-action checkboxes (origin's
"Preserve checkbox state across Turbo morphs" commits).

**Default:** **For any element that holds user input across broadcast cycles,
either (a) wrap it in `data-turbo-permanent` if it's a one-instance dialog or
preserved island, or (b) write a morph-aware Stimulus controller that
re-syncs the input state on `turbo:morph` from a stable store (sessionStorage,
URL params, a data-attribute on a permanent element).** Don't rely on the
morph algorithm preserving form state via DOM matching alone — it doesn't.

### 3. Cable adapter mismatch (dev vs prod)
**Bug:** The default `async` adapter is in-process — broadcasts from `bin/jobs`
(the worker) never reach the browser's `bin/rails server` WebSocket subscriber.
Symptom: in dev, transcript chunks appear in DB but don't stream into the page.
Hit early in the project (commit `ced3a65`-ish era).

**Default:** **Use `solid_cable` everywhere — dev, prod, and test if you wire
WebSocket-mediated specs.** Already done. Don't revert.

### 4. `data-turbo-permanent` placement traps
**Subtle:** Marking an element permanent prevents Turbo morph from replacing
it, but it ALSO prevents Stimulus controllers nested inside it from being
re-evaluated on morph. If your permanent element holds a Stimulus controller
that should re-init on a URL change, this stops working silently.

**Default:** **Use `data-turbo-permanent` only on the smallest possible
element.** Don't wrap whole sections. The transcript container, the dialog
itself, the checkbox row — each scoped tightly so the surrounding morph still
re-renders everything around it.

### 5. `broadcasts_refreshes` on hot models = unnecessary churn
**Pattern, not a bug yet:** `Run#broadcasts_refreshes_to [user, "jobs"]` fires
on every `Run` save — including heartbeat updates if `last_heartbeat_at` is
touched. With N active Runs across a busy user's dashboard, that's N
broadcasts per heartbeat interval, each morphing the entire dashboard page.
On a quiet user this is fine; on a heavy day it's perceptible "flicker" /
"feels busy."

**Default:** **For heartbeat-style updates, prefer targeted `broadcasts_to`
with a small replace/append target over `broadcasts_refreshes` that morphs
the whole page.** Or guard the broadcast with `if: -> { saved_change_to_state? }`
so heartbeat-only saves don't trigger broadcasts. Audit individual broadcasters
when the page they feed feels chattery.

## Latent risks worth tracking (not blocking, but worth fixing)

### Risk A: `epic_graph_drawer_body` frame has no explicit target
The frame at `home/index.html.erb:783` lacks `target: "_top"`. The frame only
has ONE inbound link (the "Show dependency graph" menu item) which explicitly
targets the frame, so there's no current bug. But the convention says: every
frame opts into "_top" as default, then in-frame links say so explicitly.
Make it consistent.

### Risk B: `Run` broadcasts fire on every save (incl. heartbeats)
See gotcha 5 above. On a user with 50 active Runs polling heartbeat every few
seconds, the dashboard morphs constantly. Guard the broadcast with
`saved_change_to_state?` or downgrade to a targeted `broadcasts_to` for state
changes only. The `broadcasts_refreshes` to `job` is fine (Job-show pages need
heartbeat updates); it's the dashboard fan-out (`[user, "jobs"]`) that's the
issue.

### Risk C: `epic_graph_drawer_body` frame is loaded for every Epic row's menu
Each Epic in the dashboard renders a "Show dependency graph" link targeting
the frame. Clicking one renders the graph in-place. Fine. But the frame
itself exists once at page level — if multiple Epic rows have menus, all of
them target the same frame instance. Convention worth documenting.

### Risk D: Morph-aware Stimulus controllers without tests
The `chip_bar_controller` and `bulk_jobs_controller` both have morph-restoration
logic — neither has a JS test exercising the morph cycle. A regression that
breaks chip-bar state preservation would only surface manually.

### Resolved: chat message/header/control streams moved to app events
The canonical `/chats/:id` route is React. Live chat message tail,
header, and control updates now arrive as typed app events and are
rendered on the frontend, so Rails no longer renders those Turbo Stream
partials on every message. The legacy ERB fallback keeps only the
whiteboard Turbo stream.

## Defensive defaults — what we should standardize

These are the ones worth making "the default" through code changes rather than
just documentation:

1. **Wrap `turbo_frame_tag` in a helper that defaults `target: "_top"`.**
   Force a kwarg `target:` so the caller has to choose. Or use the bare tag
   with the convention documented. Either way: no more silent default to
   in-frame.

2. **Define `broadcasts_refreshes_to_dashboard` model concern** that calls
   `broadcasts_refreshes_to` with `if: :saved_change_to_dashboard_relevant?`
   so the model itself declares what changes are worth a dashboard morph.
   Stops heartbeat fan-out.

3. **Audit + fix Risk A** (`epic_graph_drawer_body` frame gets `target:
   "_top"`).

4. **Convention in CLAUDE.md** for when to use `data-turbo-permanent` and
   when to write a morph-aware Stimulus controller. Saves the next person
   from re-discovering the form-state-loss class.

5. **JS spec coverage for morph-aware controllers.** Mock a Turbo morph
   event, assert state survives. `chip_bar` and `bulk_jobs` first.

## How to use this doc

When introducing a new frame, broadcast, stream subscription, or
`data-turbo-permanent` annotation:

1. Add it to the corresponding table above.
2. Read the "Gotchas" section and confirm the new usage doesn't trip a
   known one.
3. If the new usage exposes a class of bug we haven't seen yet: document
   the gotcha here and the defensive default that prevents it.

Goal: the next Turbo bug should be a NEW class, not a re-discovery.
