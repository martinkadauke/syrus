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
| `/` | `home#index` | `spa-core` | React dashboard shell target. Must preserve subject/view/filter/page URL state. |
| `/dashboard` | `home#index` | `spa-core` | Same dashboard surface as root. |
| `/dashboard/epics` | `home#epics` | `spa-core` | Move into React dashboard route tree. |
| `/dashboard/jobs` | `home#jobs` | `spa-core` | Move into React dashboard route tree. |
| `/dashboard/workflows` | `home#workflows` | `spa-core` | Move into React dashboard route tree. |
| `PATCH /dashboard/preferences` | `home#update_preferences` | `app-api-needed` | Browser command endpoint under `/api/v1/app/dashboard/preferences`. |
| `POST /dashboard/jobs/bulk` | `home#bulk_jobs` | `app-api-needed` | Browser command endpoint under `/api/v1/app/dashboard/jobs/bulk`. |
| `POST /dashboard/landing_pause` | `home#toggle_landing_pause` | `app-api-needed` | Browser command endpoint; dashboard state refetch after success. |
| `PATCH /dashboard/epics/:id/auto_approval` | `home#update_epic_auto_approval` | `app-api-needed` | Browser command endpoint; include capability/status in epic payload. |
| `/app-shell` | `spa#show` | `spa-core` | Hidden authenticated React shell used to prove the SPA asset, bootstrap API, and client routing path before taking over production routes. |
| `/jobs/new` | `spa#show` + `/api/v1/app/jobs/new`, `POST /api/v1/app/jobs` | `spa-core` | Migrated to the React direct-job form. Legacy ERB fallback lives at `/jobs/new/legacy` and posts to `/jobs/legacy`; `POST /jobs` remains as HTML command compatibility. |
| `/jobs/:id` | `jobs#show` | `spa-core` | High-risk page. Needs split queries for job detail, logs, workflows, attachments. |
| `/jobs/:id/source` | `jobs#source` | `spa-core` | Source browser. Needs compact tree API and lazy file loading. |
| job member commands | `jobs#start`, `#run_again`, `#restart`, `#cancel`, `#approve`, `#unapprove`, `#reopen`, `#poll_feedback`, `#rebase`, `#check_mergeability`, `#resume`, `#stop_run`, `#retry_step`, `#push_commits`, `#add_tag`, `#remove_tag`, `#diagnose`, `#add_dependency`, `#remove_dependency`, `#override_dependencies`, `#stack_base`, `#mark_valid` | `app-api-needed` | Prefer explicit command endpoints unless a generic job command endpoint stays simpler and well-typed. Every endpoint must re-check AASM guards. |
| `/jobs/:id/runs/:run_id/grade_log` | `jobs#grade_log` | `spa-core` | Either nested detail API or downloadable/log panel endpoint. |
| `/jobs/:job_id/attachments` | `job_attachments#create/destroy` | `app-api-needed` | Browser upload/delete endpoint with progress/error state. |
| `/jobs/:job_id/pin` | `job_pins#create/destroy` | `app-api-needed` | Small command endpoint; can be optimistic. |
| `/epics/:id` | `epics#show` | `spa-core` | Detail page plus child jobs/dependency graph. |
| `/epics/new`, `/epics/:id/edit` | `spa#show` + `/api/v1/app/epics*` | `spa-core` | Migrated to the React Epic form. Legacy ERB fallback lives at `/epics/new/legacy` and `/epics/:id/edit/legacy`; HTML `POST/PATCH /epics` remains for fallback. |
| `PATCH /epics/:id/archive` | `epics#archive` | `app-api-needed` | Command endpoint. |
| `PATCH /epics/:id/state` | `epics#update_state` | `app-api-needed` | Existing JSON support can inform browser endpoint shape. |
| `/epics/:id/graph` | `epics#graph` | `spa-core` | Graph data endpoint or React route depending current response shape. |
| `/epics`, `/jobs`, `/workflows` redirects | route redirects | `legacy-html` | Can be removed or changed once React router owns canonical dashboard paths. |
| `/repositories` | `spa#show` + `/api/v1/app/repositories` | `spa-core` | Migrated to the React repository list with app API poll/archive/unarchive commands. Legacy ERB fallback lives at `/repositories/legacy`. |
| `/repositories/new`, `/repositories/:id/edit`, `POST/PATCH /repositories` | `spa#show` + `/api/v1/app/repositories*` | `spa-core` | Migrated to the React repository form with app API GitHub owner/repo/branch selectors. Legacy ERB fallback lives at `/repositories/new/legacy` and `/repositories/:id/edit/legacy`; HTML `POST/PATCH /repositories` remains for fallback. |
| `/repositories/:id` | `repositories#show` | `spa-core` | Repository detail, jobs table, notes, install status, issue browser links. |
| repository collection JSON helpers | `/api/v1/app/repositories/owners`, `/repos`, `/branches` | `spa-core` | React repository form uses app API selectors; legacy AJAX helpers remain for the ERB fallback. |
| repository commands | `repositories#poll`, `#archive`, `#unarchive`, `#retry_failed_jobs` | `app-api-needed` | Command endpoints, invalidate repository and dashboard queries. |
| repository GitHub issues | `repositories#issues`, `#comment_issue`, `#close_issue`, `#delegate_issue`, `#bulk_issues` | `spa-core` + `app-api-needed` | Keep single and bulk behavior in sync. Likely own React subroute under repository detail. |
| repository notes | `repositories/notes#create/destroy` | `app-api-needed` | Small command endpoints. |
| repository documents | `spa#show` + `/api/v1/app/repositories/:id/documents` | `spa-core` | Migrated to the React repository documents page with app API upload/delete. Legacy ERB fallback lives at `/repositories/:id/documents/legacy`. |
| repository scheduled task helpers | `spa#show` + `/api/v1/app/repositories/:id/scheduled_tasks*` | `spa-core` | Migrated to React for the per-repository scheduled-task tab and repository-scoped new form. Legacy ERB fallback lives at `/repositories/:id/scheduled_tasks/legacy`. |
| `/chats/new`, `POST /chats` | `spa#show` + `/api/v1/app/chats/new`, `POST /api/v1/app/chats` | `spa-core` | Migrated to the React chat creation form. Legacy ERB fallback lives at `/chats/new/legacy`; HTML `POST /chats` remains for fallback. |
| `/chats/:id` | `spa#show` + `/api/v1/app/chats/:id` | `spa-core` | Migrated to the React chat renderer with app API message sending and app-event invalidation for new messages. Legacy ERB fallback lives at `/chats/:id/legacy`. |
| chat commands | `chats#messages`, `#create_bookmark`, `#add_attachment`, `#destroy_attachment`, `#confirm_proposal`, `#reject_proposal`, `#confirm_pending_action`, `#destroy_pending_action` | `app-api-needed` | Message send/stop/refresh/reset moved to app API with the React chat renderer; convert the remaining Turbo/HTML responses to typed browser JSON. |
| chat whiteboard | `chat_whiteboards#show/update` | `spa-core` + `app-api-needed` | Already JSON-shaped. Move under app API or adapt in place when chat migrates. |
| `/scheduled_tasks` | `spa#show` + `/api/v1/app/scheduled_tasks*` | `spa-core` | Migrated to the React scheduled-task CRUD shell. Legacy ERB fallback lives at `/scheduled_tasks/legacy`. |
| scheduled task commands | `/api/v1/app/scheduled_tasks/:id/*` | `spa-core` | React uses app API command endpoints for pause, resume, fire-now, update, and archive. Legacy HTML commands remain for fallback. |
| `/cron_templates` | `spa#show` | `spa-core` | Migrated to the React cron-template CRUD shell. Legacy ERB fallback lives at `/cron_templates/legacy`. |
| `/smart_folders` | `spa#show` | `spa-core` | Migrated to the React smart-folder manage shell. Legacy ERB fallback lives at `/smart_folders/legacy`; dashboard save forms still use `POST /smart_folders`. |
| `/tags` | `spa#show` | `spa-core` | Migrated to the React tags shell. Legacy ERB fallback lives at `/tags/legacy`. |
| `/filters/fk_options` | `filters/fk_options#index` | `app-api-needed` | Existing JSON-ish helper. Normalize response shape before React forms rely on it. |
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
| `/bug_reports` | `bug_reports#create` | `app-api-needed` | Current controller already supports JSON. SPA chrome can call JSON path. |
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
