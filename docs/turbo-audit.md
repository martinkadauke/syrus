# Turbo audit - current usage, gotchas, defensive defaults

Snapshot of Turbo touchpoints after the React SPA migration retired the
ERB dashboard, repository, Epic, scheduled-task, settings, admin, and chat
fallback pages. Turbo is now only supporting the remaining legacy HTML
surfaces, mainly Job detail/source plus auth/static pages.

## Surface Area

### Turbo Frames

There are no application `<turbo-frame>` instances left in active views.
`TurboHelper#safe_turbo_frame` remains for compatibility and tests, but no
route currently renders a frame.

### Morph-On-Broadcast

`app/views/layouts/application.html.erb` still enables
`turbo_refreshes_with method: :morph, scroll: :preserve` for legacy HTML
pages. The SPA layout does not enable Turbo refresh morphing.

### Turbo Stream Subscriptions

| Page | Streams |
|---|---|
| `jobs/show` legacy fallback | `job`, `[job, "logs"]` |

All driven by Action Cable. The adapter remains `solid_cable` in both dev
and prod (`config/cable.yml`) so worker-process broadcasts can reach browser
subscribers.

### Models That Broadcast

| Model | Mechanism | Legacy consumers |
|---|---|---|
| `Job` | `broadcasts_refreshes` plus dashboard/repository fan-out streams | Job show |
| `Run` | `broadcasts_refreshes_to job` plus dashboard fan-out stream | Job show |
| `Epic` | `broadcasts_refreshes` plus dashboard/repository fan-out streams | No active Turbo subscriber after dashboard/Epic fallback removal |
| `RunHealthSnapshot` | targeted `broadcasts_refreshes_to` | Job show |
| `SpawnedProcess` | `broadcasts_refreshes` | No active Turbo subscriber after admin fallback removal |
| `JobLog` | `broadcasts_to [log.run.job, "logs"]`, append | Job show transcript |

Some fan-out streams remain on models even though their legacy dashboard/admin
subscribers are gone. They are harmless but can be removed when the final
legacy HTML cleanup pass deletes Turbo entirely.

### `data-turbo-permanent`

Elements explicitly preserved through morph cycles:

| Element | View | Why |
|---|---|---|
| Live transcript container `run_<id>_logs` | `jobs/_step.html.erb` | Holds appended JobLog entries; morph would wipe them between broadcasts |
| Retry-context dialog | `jobs/show.html.erb` | In-flight form state survives broadcast morphs |
| Bug-report dialog + button | `shared/_bug_report_button.html.erb` | Typed message + screenshot survive |
| Footer Syrus quote | `layouts/application.html.erb` | Cosmetic; stops random quote flicker on refresh morphs |

### Morph-Aware Stimulus Controllers

Controllers that listen for Turbo morph/render events:

- `checkbox_persistence_controller.js`
- `details_persistence_controller.js`
- `tabs_controller.js`
- `iteration_tabs_controller.js`

Dashboard-only morph controllers (`chip_bar`, `bulk_jobs`, `column_picker`,
`sort_select`, `kanban`, `epic_graph_drawer`, `filter_memory`) were removed
with the ERB dashboard fallback.

## Gotchas

### Frame Target Inheritance

A `<turbo-frame>` propagates its target to links inside it. If frames are
reintroduced, default them to `target: "_top"` unless the frame's whole
purpose is in-place navigation.

### Page Morph Wipes Form State

A `broadcasts_refreshes` update can replace form elements while the operator
is typing or selecting. Use a narrowly scoped `data-turbo-permanent` island
for one-instance dialogs, or a morph-aware Stimulus controller backed by a
stable store for repeated controls.

### Cable Adapter Mismatch

The `async` adapter is process-local. Keep `solid_cable` in dev and prod so
worker broadcasts reach browser subscribers.

### `data-turbo-permanent` Placement

Use `data-turbo-permanent` on the smallest possible element. Wrapping a whole
section prevents normal Stimulus reinitialization inside that section after a
morph.

### Hot Model Broadcast Churn

`Run` and `Job` still broadcast frequently enough to affect legacy Job pages.
For heartbeat-style updates, prefer targeted append/replace streams or guard
refresh broadcasts with meaningful state-change predicates.

## Defensive Defaults

1. Avoid adding new Turbo frames during the SPA migration.
2. Keep user-input islands tiny and explicit when legacy morphing is involved.
3. Prefer app events plus TanStack Query invalidation for React routes.
4. Remove legacy Turbo broadcasts once the Job fallback is retired.
