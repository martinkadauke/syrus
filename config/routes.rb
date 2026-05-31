Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resources :users, only: %i[ new create ]

  resource :credentials, only: %i[ edit update ] do
    post :rotate_api_token
    delete :revoke_api_token
  end
  resources :account_documents, path: "account/documents", only: %i[ create destroy ]

  # Admin REST API. Token-based auth (per-user), JSON only.
  # See docs/plans/complete/admin-diagnostics.md for the endpoint plan.
  namespace :api do
    namespace :v1 do
      namespace :app do
        get "bootstrap", to: "bootstrap#show"

        namespace :admin do
          get "overview", to: "overview#show"
          get "queue/:tab", to: "queue#show", as: :queue, constraints: { tab: /active|pending|failed|recurring|workers/ }
          post "queue/reap_stale_runs", to: "queue#reap_stale_runs"
          get "stuck", to: "stuck#index"
          resources :processes, only: %i[ index show ], controller: "spawned_processes" do
            member do
              post :kill
            end
          end
          get "runs/:run_id/transcript", to: "transcripts#show"
          resources :users, only: %i[ index show ] do
            member do
              post :pause_scheduling
              post :unpause_scheduling
            end
          end
          get  "console", to: "console#show"
          post "console/pause_polling", to: "console#pause_polling"
          post "console/unpause_polling", to: "console#unpause_polling"
          post "console/pause_runs", to: "console#pause_runs"
          post "console/unpause_runs", to: "console#unpause_runs"
          post "console/clear_github_cache", to: "console#clear_github_cache"
          get "installations", to: "installations#index"
          post "installations/refresh", to: "installations#refresh"
          resources :invitations, only: %i[ index create destroy ]
          get "settings", to: "settings#show"
          patch "settings", to: "settings#update"
          post "settings/clear_secret", to: "settings#clear_secret"
        end
      end

      namespace :admin do
        # `#show` returns the deep-nested Job state (workflows + steps
        # + runs + diagnostics + claude_session metadata). `#index`
        # is a compact list — supports `?pr_number=`, `?issue_number=`,
        # `?repo=owner/name`, `?state=` to find a Job from external
        # references (a GH PR url, an issue link, etc.) so the agent
        # doesn't have to know the Syrus internal Job ID up front.
        resources :jobs, only: %i[ show index ]

        # Epic read API. `#index` is compact (filter via ?state=,
        # ?repo=owner/name, ?user=, ?has_unfinished_children=true);
        # `#show` returns the full epic with child jobs + dependency
        # edges + pending dependency refs.
        resources :epics, only: %i[ show index ]

        # Compact list of Runs for cross-Job investigations
        # ("show me everything that failed in the last hour"
        # without walking each Job's response). Filters via
        # ?state, ?since, ?trigger_kind, ?job_id; default ordering
        # is most-recently-finished first. Pagination via ?page +
        # ?per (max 100).
        get "runs", to: "runs#index"

        # Transcripts (mirror Admin::TranscriptsController; A in
        # docs/plans/complete/admin-diagnostics.md). Paginated event stream
        # via ?page= + ?per=, plus a raw-JSONL pass-through.
        get "runs/:run_id/transcript",     to: "transcripts#show"
        get "runs/:run_id/transcript/raw", to: "transcripts#raw"

        # Queue introspection (mirror Admin::QueueController; B).
        get  "queue/active",              to: "queue#active"
        get  "queue/pending",             to: "queue#pending"
        get  "queue/failed",              to: "queue#failed"
        get  "queue/recurring",           to: "queue#recurring"
        get  "queue/workers",             to: "queue#workers"
        post "queue/reap_stale_runs",     to: "queue#reap_stale_runs"

        # Overview + stuck list (mirror F).
        get "overview", to: "overview#show"
        get "stuck",    to: "overview#stuck"

        # Operator console kill switches.
        get  "console",                 to: "console#show"
        post "console/pause_polling",   to: "console#pause_polling"
        post "console/unpause_polling", to: "console#unpause_polling"
        post "console/pause_runs",      to: "console#pause_runs"
        post "console/unpause_runs",    to: "console#unpause_runs"

        # Per-instance version info — returns the SHA + role of the
        # pod handling THIS request (`request_handler`) plus every
        # other live instance (`instances`) with a fresh heartbeat.
        # Use to verify a deploy has finished rolling: during a
        # rolling deploy you'll see both old + new SHAs simultaneously.
        get "version", to: "versions#index"

        # User directory (mirror Admin::UsersController).
        resources :users, only: %i[ index show ]

        # Workflow control — the same mutations the HTML admin UI
        # exposes, but available programmatically. The :show action
        # returns one Workflow's full state (steps + runs +
        # diagnostics) without dragging in every sibling workflow
        # the way `/api/v1/admin/jobs/:id` does.
        get  "workflows/:id",                   to: "workflows#show"
        post "workflows/:id/retry_step",        to: "workflows#retry_step"
        post "workflows/:id/cleanup_workspace", to: "workflows#cleanup_workspace"

        # Subprocess inventory — see Admin::SpawnedProcessesController.
        # Index supports ?state=running|finished|all (default
        # "active_or_recent"), ?kind=, ?hostname=, ?since=,
        # ?run_id=, ?workflow_id=. Detail returns the same payload
        # plus host metrics (cpu_percent, rss_bytes) when running.
        # Kill flips kill_requested_at — the owning worker pod
        # polls that flag and terminates the local pid; the response
        # returns the updated row immediately.
        resources :processes, only: %i[ index show ], controller: "spawned_processes" do
          member do
            post :kill
          end
        end
      end
    end
  end
  resources :repositories, except: [ :destroy ] do
    collection do
      get :owners
      get :repos
      get :branches
    end
    member do
      post :poll
      post :archive
      post :unarchive
      post :retry_failed_jobs
      get  :issues
      post :comment_issue
      post :close_issue
      post :delegate_issue
      post :bulk_issues
    end
    # Repository-scoped chat routes were retired — the chat surface is
    # the top-level /chats/* resource (see `resources :chats` below).
    # The repository chat home (no tab, no UI entry point) is gone;
    # the per-repo controller was pure duplication of ChatsController.
    resources :notes, only: %i[ create destroy ], controller: "repositories/notes"
    resources :documents, only: %i[ index create destroy ], controller: "repositories/documents", shallow: true
    resources :scheduled_tasks, only: %i[ index update destroy ], controller: "repositories/scheduled_tasks"
    resources :scheduled_tasks, only: %i[ new create ]
  end

  resources :chats, only: %i[ new create show ] do
    get  :messages
    post :message
    post :stop
    post :refresh
    post :reset
    post :bookmarks, action: :create_bookmark
    post :attachments, action: :add_attachment
    delete "attachments/:attachment_id", action: :destroy_attachment, as: :attachment
    post "proposals/:proposal_id/confirm", action: :confirm_proposal, as: :proposal_confirm
    post "proposals/:proposal_id/reject", action: :reject_proposal, as: :proposal_reject
    post "pending_actions/:pending_action_id/confirm", action: :confirm_pending_action, as: :pending_action_confirm
    delete "pending_actions/:pending_action_id", action: :destroy_pending_action, as: :pending_action
    resource :whiteboard, only: %i[ show update ], controller: "chat_whiteboards"
  end

  resources :scheduled_tasks, only: %i[ index show edit update destroy ] do
    member do
      post :pause
      post :resume
      post :fire_now    # manually fire an active task without waiting for cron
    end
  end
  get "filters/fk_options", to: "filters/fk_options#index"
  get "app-shell", to: "spa#show", as: :app_shell
  get "app-shell/*path", to: "spa#show", as: :app_shell_route
  get "dashboard", to: "home#index"
  patch "dashboard/preferences", to: "home#update_preferences", as: :dashboard_preferences
  get "dashboard/epics", to: "home#epics", as: :dashboard_epics
  patch "dashboard/epics/:id/auto_approval", to: "home#update_epic_auto_approval", as: :dashboard_epic_auto_approval
  get "dashboard/jobs", to: "home#jobs", as: :dashboard_jobs
  post "dashboard/landing_pause", to: "home#toggle_landing_pause", as: :toggle_landing_pause
  get "dashboard/workflows", to: "home#workflows", as: :dashboard_workflows
  get "jobs", to: redirect(status: 302) { |_params, request|
    query = request.query_parameters.except("subject").to_query
    query.present? ? "/?subject=job&#{query}" : "/?subject=job"
  }
  get "workflows", to: redirect(status: 302) { |_params, request|
    query = request.query_parameters.except("subject").to_query
    query.present? ? "/?subject=workflow&#{query}" : "/?subject=workflow"
  }

  get "epics", to: redirect(status: 302) { |_params, request|
    query = request.query_parameters.except("subject").to_query
    query.present? ? "/?subject=epic&#{query}" : "/?subject=epic"
  }, as: :epics
  resources :epics, only: %i[ show new create edit update ] do
    member do
      patch :archive
      patch :state, action: :update_state
    end
  end
  resources :smart_folders, only: %i[ index create update destroy ]
  resources :tags, only: %i[ index create update destroy ]
  resources :cron_templates
  get "invitations", to: "spa#show", as: :invitations
  post "invitations", to: "invitations#create"
  delete "invitations/:id", to: "invitations#destroy", as: :invitation, constraints: { id: /\d+/ }
  get "invitations/legacy", to: "invitations#index", as: :legacy_invitations
  post "invitations/legacy", to: "invitations#create"
  delete "invitations/legacy/:id", to: "invitations#destroy", as: :legacy_invitation, constraints: { id: /\d+/ }
  # Legacy compatibility: the account menu's `/settings` entry is the
  # per-user credentials page. App-wide settings live at `/settings/edit`
  # and remain admin-only.
  get "settings", to: "credentials#edit"
  get "settings/edit", to: "spa#show", as: :edit_settings
  patch "settings", to: "settings#update"
  get "settings/edit/legacy", to: "settings#edit", as: :legacy_edit_settings
  patch "settings/legacy", to: "settings#update", as: :legacy_settings
  resources :bug_reports, only: %i[ create ]
  resources :jobs, only: %i[ show new create ] do
    resource :pin, only: %i[ create destroy ], controller: "job_pins"
    resources :attachments, only: %i[ create destroy ], controller: "job_attachments"

    member do
      post :start
      post :run_again      # soft retry — new Run on the existing branch
      post :restart        # hard reset — close this thread, open a new one with a fresh branch + PR
      post :cancel         # cancel active runs + close the thread
      post :approve        # implemented → approved, by operator action
      post :unapprove      # approved → implemented, until landing starts
      post :reopen         # undo a close — closed → open, polling resumes
      post :poll_feedback  # manually trigger PollPullRequestJob for this Job
      post :rebase         # manually trigger a rebase Run on this Job's PR
      post :check_mergeability  # ask GitHub for the latest mergeable status now
      post :resume         # continue a failed Run via claude --resume
      post :stop_run       # cancel a single active Run without closing the thread
      post :retry_step     # re-run the failed step in a failed Workflow (keeps the existing workspace)
      post :push_commits   # push uncommitted/committed local changes from a failed Workflow's workspace
      post :tags, action: :add_tag
      delete "tags/:tag_id", action: :remove_tag, as: :tag
      get  :source         # browse the repo source at any branch commit or merge base
      post :diagnose       # capture a RunHealthSnapshot for an active Run
      get  "runs/:run_id/grade_log", action: :grade_log, as: :run_grade_log
      post :dependencies, action: :add_dependency
      delete "dependencies/:dependency_id", action: :remove_dependency, as: :dependency
      post :override_dependencies
      patch :stack_base
      post :mark_valid
    end
  end
  resources :epics, only: [] do
    member do
      get :graph
    end
  end

  get "admin", to: "spa#show", as: :admin_root
  get "admin/queue", to: "spa#show", as: :admin_queue_root
  get "admin/queue/:tab", to: "spa#show", as: :admin_queue, constraints: { tab: /active|pending|failed|recurring|workers/ }
  get "admin/stuck", to: "spa#show", as: :admin_stuck
  get "admin/processes", to: "spa#show", as: :admin_processes
  get "admin/processes/:id", to: "spa#show", as: :admin_process, constraints: { id: /\d+/ }
  post "admin/processes/:id/kill", to: "admin/spawned_processes#kill", as: :kill_admin_process, constraints: { id: /\d+/ }
  get "admin/runs/:run_id/transcript", to: "spa#show", as: :admin_run_transcript, constraints: { run_id: /\d+/ }
  get "admin/users", to: "spa#show", as: :admin_users
  get "admin/users/:id", to: "spa#show", as: :admin_user, constraints: { id: /\d+/ }
  post "admin/users/:id/pause_scheduling", to: "admin/users#pause_scheduling", as: :pause_scheduling_admin_user, constraints: { id: /\d+/ }
  post "admin/users/:id/unpause_scheduling", to: "admin/users#unpause_scheduling", as: :unpause_scheduling_admin_user, constraints: { id: /\d+/ }
  get "admin/console", to: "spa#show", as: :admin_console
  get "admin/installations", to: "spa#show", as: :admin_installations
  post "admin/installations/refresh", to: "admin/installations#refresh", as: :admin_installations_refresh

  namespace :admin do
    # System overview — landing page for the admin area.
    # See docs/plans/complete/admin-diagnostics.md (F).
    get "legacy", to: "overview#show", as: :legacy_overview

    # Per-Run claude transcript viewer — renders the captured
    # ClaudeSession.transcript_jsonl as a structured event stream.
    # See docs/plans/complete/admin-diagnostics.md (A).
    get  "runs/:run_id/transcript/legacy",   to: "transcripts#show",     as: :legacy_run_transcript
    get  "runs/:run_id/transcript/download", to: "transcripts#download", as: :run_transcript_download

    # SolidQueue inspector — see docs/plans/complete/admin-diagnostics.md (B).
    get  "queue/legacy",                  to: "queue#index", as: :legacy_queue_root
    get  "queue/legacy/:tab",             to: "queue#show",            as: :legacy_queue, constraints: { tab: /active|pending|failed|recurring|workers/ }
    post "queue/reap_stale_runs",         to: "queue#reap_stale_runs", as: :reap_stale_runs
    post "queue/legacy/reap_stale_runs",  to: "queue#reap_stale_runs", as: :legacy_reap_stale_runs

    # Stuck-things watchlist — Run heartbeat stale or Workflow
    # nearing prune. See Admin::StuckItems for the definition.
    get "stuck/legacy", to: "stuck#index", as: :legacy_stuck

    # Subprocess inventory legacy ERB fallback — see Admin::SpawnedProcessesController.
    get  "processes/legacy",          to: "spawned_processes#index", as: :legacy_processes
    get  "processes/legacy/:id",      to: "spawned_processes#show",  as: :legacy_process
    post "processes/legacy/:id/kill", to: "spawned_processes#kill",  as: :legacy_kill_process

    get  "installations/legacy",         to: "installations#index",   as: :legacy_installations
    post "installations/legacy/refresh", to: "installations#refresh", as: :legacy_installations_refresh

    # User directory — filterable list + per-user detail page.
    # Drilled into from the GH rate-limits tile on /admin (with
    # `?gh_rate=low`); also supports `?admin=true|false`,
    # `?email=substr`, `?has_github_token=true|false`,
    # `?has_claude_token=true|false`. Filter logic lives in
    # Admin::UsersFilter so the API mirror reuses it.
    get  "users/legacy",                         to: "users#index", as: :legacy_users
    get  "users/legacy/:id",                     to: "users#show",  as: :legacy_user
    post "users/legacy/:id/pause_scheduling",   to: "users#pause_scheduling", as: :legacy_pause_user_scheduling
    post "users/legacy/:id/unpause_scheduling", to: "users#unpause_scheduling", as: :legacy_unpause_user_scheduling

    # Operator console — kill switches + audit log (L).
    get  "console/legacy",             to: "console#show",              as: :legacy_console
    post "console/pause_polling",      to: "console#pause_polling",     as: :pause_polling
    post "console/unpause_polling",    to: "console#unpause_polling",   as: :unpause_polling
    post "console/pause_runs",         to: "console#pause_runs",        as: :pause_runs
    post "console/unpause_runs",       to: "console#unpause_runs",      as: :unpause_runs
    post "console/clear_github_cache", to: "console#clear_github_cache", as: :clear_github_cache
    post "console/legacy/pause_polling",      to: "console#pause_polling",     as: :legacy_pause_polling
    post "console/legacy/unpause_polling",    to: "console#unpause_polling",   as: :legacy_unpause_polling
    post "console/legacy/pause_runs",         to: "console#pause_runs",        as: :legacy_pause_runs
    post "console/legacy/unpause_runs",       to: "console#unpause_runs",      as: :legacy_unpause_runs
    post "console/legacy/clear_github_cache", to: "console#clear_github_cache", as: :legacy_clear_github_cache

    get "github_app/register", to: "github_app#register", as: :github_app_register
    get "github_app/callback", to: "github_app#callback", as: :github_app_callback
    get "github_app/confirm",  to: "github_app#confirm",  as: :github_app_confirm
  end

  post "dashboard/jobs/bulk", to: "home#bulk_jobs", as: :bulk_dashboard_jobs
  root "home#index"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
