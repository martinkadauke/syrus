# React SPA route inventory

_Captured 2026-05-30 as M0 for `react-spa-migration.md`._

This inventory groups the current Rails routes into migration buckets.
It is not a pasted `bin/rails routes` dump; the source of truth remains
`config/routes.rb`. The goal is to make route ownership explicit before
React starts taking paths over.

`bin/rails routes --expanded` currently reports 241 routes including
Rails engine routes. Application routes occupy routes 1-215. The rest
are Turbo Native helpers, Action Mailbox, Active Storage, and Rails
health/storage internals.

## Buckets

| Bucket | Meaning |
|---|---|
| `spa-core` | Authenticated operator route that must become a React route. |
| `spa-admin` | Authenticated admin route that should migrate early, but can trail core operator routes where needed. |
| `legacy-html` | Keep server-rendered until late cleanup; either low value for SPA or part of auth/external flows. |
| `external-html` | Intentionally HTML because a third-party or Rails engine owns the flow. |
| `api-existing` | Existing token API. Keep stable for external callers; reuse service/serializer code only when appropriate. |
| `app-api-needed` | No browser JSON equivalent yet; add under `/api/v1/app/*` before migrating the owning page. |
| `engine` | Framework route, not part of the SPA migration. |

## Route groups

| Route group | Current owner | Bucket | Notes / target |
|---|---|---|---|
| `/` | `spa#show` + `/api/v1/app/dashboard` | `spa-core` | Migrated to the React dashboard shell. Must preserve subject/view/filter/page URL state. |
| `/dashboard` | `spa#show` + `/api/v1/app/dashboard` | `spa-core` | Same dashboard surface as root. Legacy ERB fallback lives at `/dashboard/legacy`. |
| `/dashboard/epics` | `spa#show` + `/api/v1/app/dashboard?subject=epic` | `spa-core` | Migrated to the React dashboard route tree. Legacy ERB fallback lives at `/dashboard/epics/legacy`. |
| `/dashboard/jobs` | `spa#show` + `/api/v1/app/dashboard?subject=job` | `spa-core` | Migrated to the React dashboard route tree. Legacy ERB fallback lives at `/dashboard/jobs/legacy`. |
| `/dashboard/workflows` | `spa#show` + `/api/v1/app/dashboard?subject=workflow` | `spa-core` | Migrated to the React dashboard route tree. Legacy ERB fallback lives at `/dashboard/workflows/legacy`. |
| `PATCH /dashboard/preferences` | `/api/v1/app/dashboard/preferences` | `spa-core` | App API endpoint persists sort, visible-column, and Kanban lane preferences; legacy Turbo/HTML command remains for fallback. |
| `POST /dashboard/jobs/bulk` | `/api/v1/app/dashboard/jobs/bulk` | `spa-core` | App API endpoint mirrors retry, close, approve/review, and tag bulk actions with JSON responses. Legacy HTML bulk form remains for fallback. |
| `POST /dashboard/landing_pause` | `/api/v1/app/dashboard/landing_pause` | `spa-core` | App API endpoint toggles landing pause and re-enqueues the landing processor on resume; legacy HTML command remains for fallback. |
| `PATCH /dashboard/epics/:id/auto_approval` | `/api/v1/app/dashboard/epics/:id/auto_approval` | `spa-core` | App API endpoint updates dashboard Epic auto-approval state; legacy HTML command remains for fallback. |
| `/app-shell` | `spa#show` | `spa-core` | Hidden authenticated React shell used to prove the SPA asset, bootstrap API, and client routing path before taking over production routes. |
| `/jobs/new` | `spa#show` + `/api/v1/app/jobs/new`, `POST /api/v1/app/jobs` | `spa-core` | Migrated to the React direct-job form. Legacy ERB fallback lives at `/jobs/new/legacy` and posts to `/jobs/legacy`; `POST /jobs` remains as HTML command compatibility. |
| `/jobs/:id` | `spa#show` + `/api/v1/app/jobs/:id`, `/api/v1/app/jobs/:id/timeline` | `spa-core` | Migrated to the React Job detail page. Legacy ERB fallback lives at `/jobs/:id/legacy`; HTML member commands remain for fallback/dashboard controls. |
| `/jobs/:id/source` | `spa#show` + `/api/v1/app/jobs/:id/source` | `spa-core` | Migrated to the React source tab. Legacy ERB source browser lives at `/jobs/:id/source/legacy`. |
| job lifecycle commands | `/api/v1/app/jobs/:job_id/start`, `/run_again`, `/restart`, `/cancel`, `/approve`, `/unapprove`, `/reopen` | `spa-core` | App API endpoints now cover core lifecycle transitions and emit job app-event invalidation. Legacy HTML commands remain for fallback. |
| job run/workflow commands | `jobs#poll_feedback`, `#rebase`, `#check_mergeability`, `#resume`, `#stop_run`, `#retry_step`, `#push_commits`, `#diagnose` | `spa-core` | App API mirrors are available under `/api/v1/app/jobs/:job_id/*`, `/runs/:run_id/*`, and `/workflows/:workflow_id/*`; migrate the Job detail page to these before dropping the HTML forms. |
| job metadata commands | `/api/v1/app/jobs/:job_id/tags`, `/dependencies`, `/dependencies/override`, `/stack_base`, `/mark_valid` | `spa-core` | App API endpoints now cover tag add/remove, manual dependency add/remove, dependency override, stack base update, and invalid-job requeue. Legacy HTML commands remain for fallback. |
| `/jobs/:id/runs/:run_id/grade_log` | `jobs#grade_log` | `spa-core` | Either nested detail API or downloadable/log panel endpoint. |
| `/jobs/:job_id/attachments` | `/api/v1/app/jobs/:job_id/attachments` | `spa-core` | App API upload/delete endpoints return compact attachment rows and emit job app-event invalidation. Legacy HTML attachment forms remain for fallback. |
| `/jobs/:job_id/pin` | `/api/v1/app/jobs/:job_id/pin` | `spa-core` | App API pin/unpin endpoint returns the new pin state and emits job app-event invalidation. Legacy HTML command remains for fallback. |
| `/epics/:id` | `spa#show` + `/api/v1/app/epics/:id` | `spa-core` | Migrated to the React Epic detail page with child Jobs, dependency graph data, and app API state/archive commands. Legacy ERB fallback lives at `/epics/:id/legacy`. |
| `/epics/new`, `/epics/:id/edit` | `spa#show` + `/api/v1/app/epics*` | `spa-core` | Migrated to the React Epic form. Legacy ERB fallback lives at `/epics/new/legacy` and `/epics/:id/edit/legacy`; HTML `POST/PATCH /epics` remains for fallback. |
| `PATCH /epics/:id/archive` | `/api/v1/app/epics/:id/archive` | `spa-core` | React uses the app API command endpoint; legacy HTML command remains for fallback/dashboard controls. |
| `PATCH /epics/:id/state` | `/api/v1/app/epics/:id/state` | `spa-core` | React uses the app API command endpoint; legacy HTML/JSON command remains for fallback/dashboard controls. |
| `/epics/:id/graph` | `epics#graph` | `spa-core` | Graph data endpoint or React route depending current response shape. |
| `/epics`, `/jobs`, `/workflows` redirects | route redirects | `legacy-html` | Can be removed or changed once React router owns canonical dashboard paths. |
| `/repositories` | `spa#show` + `/api/v1/app/repositories` | `spa-core` | Migrated to the React repository list with app API poll/archive/unarchive commands. Legacy ERB fallback lives at `/repositories/legacy`. |
| `/repositories/new`, `/repositories/:id/edit`, `POST/PATCH /repositories` | `spa#show` + `/api/v1/app/repositories*` | `spa-core` | Migrated to the React repository form with app API GitHub owner/repo/branch selectors. Legacy ERB fallback lives at `/repositories/new/legacy` and `/repositories/:id/edit/legacy`; HTML `POST/PATCH /repositories` remains for fallback. |
| `/repositories/:id` | `spa#show` + `/api/v1/app/repositories/:id*` | `spa-core` | Migrated to the React repository detail overview and GitHub Issues tab. Legacy ERB fallback lives at `/repositories/:id/legacy`. |
| repository collection JSON helpers | `/api/v1/app/repositories/owners`, `/repos`, `/branches` | `spa-core` | React repository form uses app API selectors; legacy AJAX helpers remain for the ERB fallback. |
| repository commands | `/api/v1/app/repositories/:id/poll`, `/archive`, `/unarchive`, `/retry_failed_jobs` | `spa-core` | React repository list and detail use app API command endpoints for poll, archive/unarchive, and retry failed jobs. Legacy HTML commands remain for fallback. |
| repository GitHub issues | `/api/v1/app/repositories/:id/issues*` | `spa-core` | React repository detail owns issue listing plus comment/close/delegate/bulk commands. Legacy HTML issue routes remain for fallback. |
| repository notes | `/api/v1/app/repositories/:id/notes`, `/api/v1/app/repositories/:repository_id/notes/:id` | `spa-core` | React repository overview uses app API mutations for note add/remove. Legacy HTML note routes remain for fallback. |
| repository documents | `spa#show` + `/api/v1/app/repositories/:id/documents` | `spa-core` | Migrated to the React repository documents page with app API upload/delete. Legacy ERB fallback lives at `/repositories/:id/documents/legacy`. |
| repository scheduled task helpers | `spa#show` + `/api/v1/app/repositories/:id/scheduled_tasks*` | `spa-core` | Migrated to React for the per-repository scheduled-task tab and repository-scoped new form. Legacy ERB fallback lives at `/repositories/:id/scheduled_tasks/legacy`. |
| `/chats/new`, `POST /chats` | `spa#show` + `/api/v1/app/chats/new`, `POST /api/v1/app/chats` | `spa-core` | Migrated to the React chat creation form. Legacy ERB fallback lives at `/chats/new/legacy`; HTML `POST /chats` remains for fallback. |
| `/chats/:id` | `spa#show` + `/api/v1/app/chats/:id`, `/api/v1/app/chats/:id/messages` | `spa-core` | Migrated to the React chat renderer with frontend Markdown rendering, typed message pagination, app API message sending, and payload-carrying app events for live message tail replacement. Legacy ERB fallback lives at `/chats/:id/legacy`. |
| chat commands | `/api/v1/app/chats/:id/bookmarks`, `/attachments`, `/proposals/:proposal_id/*`, `/pending_actions/:pending_action_id/*` | `spa-core` | React chat uses typed app API mutations for bookmarks, attachment add/remove, proposal confirm/reject, and pending-action confirm/cancel. Legacy HTML routes remain for fallback. |
| chat whiteboard | `/api/v1/app/chats/:id/whiteboard` | `spa-core` | React chat mounts the Excalidraw whiteboard, saves through the app API, and receives app-event invalidation for agent/operator updates. Legacy `chat_whiteboards#show/update` remains for fallback. |
| `/scheduled_tasks` | `spa#show` + `/api/v1/app/scheduled_tasks*` | `spa-core` | Migrated to the React scheduled-task CRUD shell. Legacy ERB fallback lives at `/scheduled_tasks/legacy`. |
| scheduled task commands | `/api/v1/app/scheduled_tasks/:id/*` | `spa-core` | React uses app API command endpoints for pause, resume, fire-now, update, and archive. Legacy HTML commands remain for fallback. |
| `/cron_templates` | `spa#show` | `spa-core` | Migrated to the React cron-template CRUD shell. Legacy ERB fallback lives at `/cron_templates/legacy`. |
| `/smart_folders` | `spa#show` | `spa-core` | Migrated to the React smart-folder manage shell. Legacy ERB fallback lives at `/smart_folders/legacy`; dashboard save forms still use `POST /smart_folders`. |
| `/tags` | `spa#show` | `spa-core` | Migrated to the React tags shell. Legacy ERB fallback lives at `/tags/legacy`. |
| `/filters/fk_options` | `/api/v1/app/filters/fk_options` | `spa-core` | Browser typeahead now uses the app API endpoint with normalized `{ options: [...] }`; legacy JSON helper remains for fallback. |
| `/credentials/edit`, `/credentials` | `spa#show` + `/api/v1/app/credentials` | `spa-core` | Migrated to the React credentials/settings page. Legacy ERB fallback lives at `/credentials/edit/legacy`; HTML mutations remain for fallback. |
| credential token commands | `/api/v1/app/credentials/*api_token` | `spa-core` | React uses app API commands returning masked token state plus one-time plaintext on rotation. Legacy HTML commands remain for fallback. |
| `/account/documents` | `/api/v1/app/credentials/documents` | `spa-core` | React uses app API upload/delete endpoints for credential-page documents. Legacy HTML controller remains for fallback. |
| `/settings` | `spa#show` | `spa-core` | Migrated as the per-user credentials alias. `/settings/edit` remains the separate admin app-settings surface. |
| `/settings/edit` | `spa#show` | `spa-admin` | Migrated to the React app settings shell. Legacy ERB fallback lives at `/settings/edit/legacy`. |
| `PATCH /settings` | `settings#update` | `legacy-html` | Kept for existing HTML controls; React uses `/api/v1/app/admin/settings`. |
| `/invitations` | `spa#show` | `spa-admin` | Migrated to the React invitations shell. Legacy ERB fallback lives at `/invitations/legacy`. |
| `/admin` | `spa#show` | `spa-admin` | Migrated to the React admin overview shell; legacy ERB fallback lives at `/admin/legacy`. |
| `/admin/queue`, `/admin/queue/:tab` | `spa#show` | `spa-admin` | Migrated to the React admin queue shell. Legacy ERB fallback lives at `/admin/queue/legacy` and `/admin/queue/legacy/:tab`. |
| `POST /admin/queue/reap_stale_runs` | `admin/queue#reap_stale_runs` | `legacy-html` | Kept for existing HTML admin controls; React uses `POST /api/v1/app/admin/queue/reap_stale_runs`. |
| `/admin/stuck` | `spa#show` | `spa-admin` | Migrated to the React stuck-items shell. Legacy ERB fallback lives at `/admin/stuck/legacy`. |
| `/admin/processes`, `/admin/processes/:id` | `spa#show` | `spa-admin` | Migrated to the React process inventory/detail shell. Legacy ERB fallback lives at `/admin/processes/legacy` and `/admin/processes/legacy/:id`. |
| `POST /admin/processes/:id/kill` | `admin/spawned_processes#kill` | `legacy-html` | Kept for existing HTML controls; React uses `POST /api/v1/app/admin/processes/:id/kill`. |
| `/admin/runs/:run_id/transcript` | `spa#show` | `spa-admin` | Migrated to the React transcript viewer. Legacy ERB fallback lives at `/admin/runs/:run_id/transcript/legacy`. |
| `/admin/runs/:run_id/transcript/download` | `admin/transcripts#download` | `legacy-html` | Keep as regular download endpoint. |
| `/admin/users`, `/admin/users/:id` | `spa#show` | `spa-admin` | Migrated to the React users list/detail shell. Legacy ERB fallback lives at `/admin/users/legacy` and `/admin/users/legacy/:id`. |
| admin user scheduling commands | `admin/users#pause_scheduling`, `#unpause_scheduling` | `legacy-html` | Kept for existing HTML controls; React uses `/api/v1/app/admin/users/:id/*_scheduling`. |
| `/admin/console` | `spa#show` | `spa-admin` | Migrated to the React operator console. Legacy ERB fallback lives at `/admin/console/legacy`. |
| admin console commands | `admin/console#pause_polling`, `#unpause_polling`, `#pause_runs`, `#unpause_runs`, `#clear_github_cache` | `legacy-html` | Kept for existing HTML controls; React uses `/api/v1/app/admin/console/*`. |
| `/admin/installations` | `spa#show` | `spa-admin` | Migrated to the React GitHub App installations page. Legacy ERB fallback lives at `/admin/installations/legacy`. |
| `POST /admin/installations/refresh` | `admin/installations#refresh` | `legacy-html` | Kept for existing HTML controls; React uses `/api/v1/app/admin/installations/refresh`. |
| `/admin/github_app/register`, `/admin/github_app/callback`, `/admin/github_app/confirm` | `admin/github_app` | `external-html` | Third-party manifest/callback flow. Leave server-rendered unless there is a concrete SPA benefit. |
| `/session/new`, `POST/DELETE /session` | `sessions` resource | `legacy-html` | Keep server-rendered until late. SPA handles 401 by navigating here. |
| `/users/new`, `POST /users` | `users#new/create` | `legacy-html` | First-user bootstrap path; low value for SPA. |
| `/passwords/new`, `/passwords/:token/edit`, password mutations | `passwords` resource | `legacy-html` | Keep server-rendered unless auth UX gets a dedicated pass. |
| `/bug_reports` | `/api/v1/app/bug_reports` | `spa-core` | Floating bug-report chrome posts to the app API; legacy HTML route remains for fallback. |
| `/pwa/*` | `app/views/pwa/*` | `legacy-html` | Static/dynamic manifest assets. |
| `/up` | `rails/health#show` | `engine` | Health check; unrelated. |
| `/api/v1/admin/*` | `api/v1/admin/*` | `api-existing` | Token-auth external/admin API. Keep stable; do not repurpose for session-cookie SPA if the browser needs different contracts. |
| Turbo Native routes | `turbo/native/navigation` | `engine` | Remove when Turbo is retired if no longer mounted by the gem. |
| Action Mailbox routes | Rails engine | `engine` | Unrelated. |
| Active Storage routes | Rails engine | `engine` | Keep for uploads/downloads. |

## Stimulus ownership by migration slice

| Slice | Controllers to retire or rewrite in React |
|---|---|
| SPA shell | `split_button`, `flash`, `bug_report`, global `form_validation` compatibility |
| Admin diagnostics | `auto_refresh`, `tabs`, `filter_memory` if used by admin filters |
| Dashboard | `chip_bar`, `column_picker`, `sort_select`, `bulk_jobs`, `kanban`, `epic_graph_drawer`, `filter_memory`, `checkbox_persistence`, `details_persistence` |
| Job detail/source | `approval_review`, `attachment_drop`, `iteration_tabs`, `retry_context`, `run_timer`, `source_highlight`, `source_tree`, `transcript_toggle` |
| Chat/whiteboard | `chat`, `chat_layout`, `chat_side_panel`, `bookmark_modal`, `whiteboard` |
| Repository/settings/forms | `repository_form`, `credentials_form`, `scheduled_task_form`, `prompt_template`, `document_upload`, `issue_comment`, `auto_submit` |
| Shared visual helpers | `mermaid_graph`, `relative_time` can become React components or small standalone utilities |

## First migration slice

Use admin diagnostics as the first real page migration after the
scaffolding/bootstrap PR:

1. `/admin` (migrated)
2. `/admin/queue/:tab` (migrated)
3. `/admin/stuck` (migrated)
4. `/admin/processes` (migrated)
5. `/admin/runs/:run_id/transcript` (migrated)

Rationale:

- The operator-facing risk is lower than `jobs/:id` and `chats/:id`.
- The existing token admin API and admin service objects already define
  much of the read model.
- Tables, filters, polling/realtime invalidation, command buttons, and
  transcript pagination exercise the SPA architecture without touching
  the agent execution loop.

## API work implied before page migration

The first implementation phase needs these app API primitives before
any page can move safely:

- `/api/v1/app/bootstrap`
- session-cookie API base controller with JSON 401/403 handling
- shared browser response/error envelope
- route-level migration flag or server-side route switch
- Action Cable JSON event envelope and one low-risk channel

After that, admin diagnostics can reuse or adapt existing admin
serializers one endpoint at a time.
