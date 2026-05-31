# Turbo audit - retired architecture notes

Snapshot after the React SPA migration retired the authenticated ERB
operator pages. Regular operator surfaces now render through
`SpaController` + React and use `/api/v1/app/*` JSON APIs with
`AppUserChannel` app events. Turbo remains only as legacy support for
auth/bootstrap pages, password reset, GitHub App registration, downloads,
and static/PWA assets.

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
| Active application views | none |

Action Cable remains important for the React app: `AppUserChannel`
delivers JSON app events to TanStack Query. The adapter remains
`solid_cable` in both dev and prod (`config/cable.yml`) so worker-process
events can reach browser subscribers.

### Models That Broadcast

| Model | Mechanism | Legacy consumers |
|---|---|---|
| `Job` | `broadcasts_refreshes` plus dashboard/repository fan-out streams | none |
| `Run` | `broadcasts_refreshes_to job` plus dashboard fan-out stream | none |
| `Epic` | `broadcasts_refreshes` plus dashboard/repository fan-out streams | none |
| `RunHealthSnapshot` | targeted `broadcasts_refreshes_to` | none |
| `SpawnedProcess` | `broadcasts_refreshes` | No active Turbo subscriber after admin fallback removal |

These broadcasts are compatibility leftovers with no active operator-page
subscribers. Remove them only alongside an explicit app-event replacement
for any live behavior the React UI still needs.

### `data-turbo-permanent`

Elements explicitly preserved through morph cycles:

| Element | View | Why |
|---|---|---|
| Bug-report dialog + button | `shared/_bug_report_button.html.erb` | Typed message + screenshot survive |
| Footer Syrus quote | `layouts/application.html.erb` | Cosmetic; stops random quote flicker on refresh morphs |

### Morph-Aware Stimulus Controllers

Controllers that listen for Turbo morph/render events:

- `checkbox_persistence_controller.js`
- `details_persistence_controller.js`

Page-specific operator controllers were removed with their ERB fallbacks.

## Gotchas

### Frame Target Inheritance

A `<turbo-frame>` propagates its target to links inside it. If frames are
reintroduced, default them to `target: "_top"` unless the frame's whole
purpose is in-place navigation.

### Page Morph Wipes Form State

A `broadcasts_refreshes` update can replace form elements while someone is
typing or selecting on a legacy HTML page. Use React state for operator
pages. If a legacy auth/external page needs morphing, use a narrowly scoped
`data-turbo-permanent` island or a morph-aware Stimulus controller backed by
a stable store.

### Cable Adapter Mismatch

The `async` adapter is process-local. Keep `solid_cable` in dev and prod so
worker broadcasts reach browser subscribers.

### `data-turbo-permanent` Placement

Use `data-turbo-permanent` on the smallest possible element. Wrapping a whole
section prevents normal Stimulus reinitialization inside that section after a
morph.

### Hot Model Broadcast Churn

`Run` and `Job` still have legacy refresh hooks. Do not use those hooks for
new live UI. React pages should receive app events and either invalidate
query keys or apply compact payloads, as chat does for message tails.

## Defensive Defaults

1. Do not add new Turbo frames for operator routes.
2. Keep user-input islands tiny and explicit when legacy morphing is involved.
3. Prefer app events plus TanStack Query invalidation for React routes.
4. Remove legacy Turbo broadcasts only after equivalent app events exist.
