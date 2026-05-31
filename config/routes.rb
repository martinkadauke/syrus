Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resources :users, only: %i[ new create ]

  resource :credentials, only: %i[ update ] do
    post :rotate_api_token
    delete :revoke_api_token
  end
  get "credentials/edit", to: "spa#show", as: :edit_credentials
  get "credentials/edit/legacy", to: "credentials#edit", as: :legacy_edit_credentials
  patch "credentials/legacy", to: "credentials#update", as: :legacy_credentials
  post "credentials/legacy/rotate_api_token", to: "credentials#rotate_api_token", as: :legacy_rotate_api_token_credentials
  delete "credentials/legacy/revoke_api_token", to: "credentials#revoke_api_token", as: :legacy_revoke_api_token_credentials
  resources :account_documents, path: "account/documents", only: %i[ create destroy ]

  # Admin REST API. Token-based auth (per-user), JSON only.
  # See docs/plans/complete/admin-diagnostics.md for the endpoint plan.
  namespace :api do
    namespace :v1 do
      namespace :app do
        get "bootstrap", to: "bootstrap#show"
        post "bug_reports", to: "bug_reports#create"
        resources :tags, only: %i[ index create update destroy ]
        resources :smart_folders, only: %i[ index update destroy ]
        resources :cron_templates, only: %i[ index show create update destroy ]
        resource :credentials, only: %i[ show update ] do
          post :clear_credential
          post :rotate_api_token
          delete :revoke_api_token
          resources :documents, only: %i[ create destroy ], controller: "credentials/documents"
        end
        get "jobs/new", to: "direct_jobs#new"
        post "jobs", to: "direct_jobs#create"
        post "jobs/:job_id/pin", to: "job_pins#create", constraints: { job_id: /\d+/ }
        delete "jobs/:job_id/pin", to: "job_pins#destroy", constraints: { job_id: /\d+/ }
        post "jobs/:job_id/attachments", to: "job_attachments#create", constraints: { job_id: /\d+/ }
        delete "jobs/:job_id/attachments/:id", to: "job_attachments#destroy", constraints: { job_id: /\d+/, id: /\d+/ }
        post "jobs/:job_id/tags", to: "job_metadata#add_tag", constraints: { job_id: /\d+/ }
        delete "jobs/:job_id/tags/:tag_id", to: "job_metadata#remove_tag", constraints: { job_id: /\d+/, tag_id: /\d+/ }
        post "jobs/:job_id/dependencies", to: "job_metadata#add_dependency", constraints: { job_id: /\d+/ }
        delete "jobs/:job_id/dependencies/:dependency_id", to: "job_metadata#remove_dependency", constraints: { job_id: /\d+/, dependency_id: /\d+/ }
        post "jobs/:job_id/dependencies/override", to: "job_metadata#override_dependencies", constraints: { job_id: /\d+/ }
        patch "jobs/:job_id/stack_base", to: "job_metadata#stack_base", constraints: { job_id: /\d+/ }
        post "jobs/:job_id/mark_valid", to: "job_metadata#mark_valid", constraints: { job_id: /\d+/ }
        get "epics/new", to: "epics#new"
        get "epics/:id", to: "epics#show", constraints: { id: /\d+/ }
        get "epics/:id/edit", to: "epics#edit", constraints: { id: /\d+/ }
        post "epics", to: "epics#create"
        patch "epics/:id", to: "epics#update", constraints: { id: /\d+/ }
        patch "epics/:id/archive", to: "epics#archive", constraints: { id: /\d+/ }
        patch "epics/:id/state", to: "epics#update_state", constraints: { id: /\d+/ }
        get "filters/fk_options", to: "filters#fk_options"
        patch "dashboard/preferences", to: "dashboard#preferences"
        post "dashboard/landing_pause", to: "dashboard#landing_pause"
        post "dashboard/jobs/bulk", to: "dashboard#bulk_jobs"
        patch "dashboard/epics/:id/auto_approval", to: "dashboard#epic_auto_approval", constraints: { id: /\d+/ }
        get "chats/new", to: "chats#new"
        post "chats", to: "chats#create"
        get "chats/:id", to: "chats#show", constraints: { id: /\d+/ }
        get "chats/:id/messages", to: "chats#messages", constraints: { id: /\d+/ }
        get "chats/:id/whiteboard", to: "chat_whiteboards#show", constraints: { id: /\d+/ }
        patch "chats/:id/whiteboard", to: "chat_whiteboards#update", constraints: { id: /\d+/ }
        post "chats/:id/message", to: "chats#message", constraints: { id: /\d+/ }
        post "chats/:id/stop", to: "chats#stop", constraints: { id: /\d+/ }
        post "chats/:id/refresh", to: "chats#refresh", constraints: { id: /\d+/ }
        post "chats/:id/reset", to: "chats#reset", constraints: { id: /\d+/ }
        post "chats/:id/bookmarks", to: "chats#create_bookmark", constraints: { id: /\d+/ }
        post "chats/:id/attachments", to: "chats#add_attachment", constraints: { id: /\d+/ }
        delete "chats/:id/attachments/:attachment_id", to: "chats#destroy_attachment", constraints: { id: /\d+/, attachment_id: /\d+/ }
        post "chats/:id/proposals/:proposal_id/confirm", to: "chats#confirm_proposal", constraints: { id: /\d+/, proposal_id: /\d+/ }
        post "chats/:id/proposals/:proposal_id/reject", to: "chats#reject_proposal", constraints: { id: /\d+/, proposal_id: /\d+/ }
        post "chats/:id/pending_actions/:pending_action_id/confirm", to: "chats#confirm_pending_action", constraints: { id: /\d+/, pending_action_id: /\d+/ }
        delete "chats/:id/pending_actions/:pending_action_id", to: "chats#destroy_pending_action", constraints: { id: /\d+/, pending_action_id: /\d+/ }
        get "repositories/new", to: "repositories#new"
        get "repositories/:id/edit", to: "repositories#edit", constraints: { id: /\d+/ }
        get "repositories/owners", to: "repositories#owners"
        get "repositories/repos", to: "repositories#repos"
        get "repositories/branches", to: "repositories#branches"
        resources :repositories, only: %i[ index show create update ] do
          member do
            get "issues", to: "repositories#issues"
            post "issues/comment", to: "repositories#comment_issue"
            post "issues/close", to: "repositories#close_issue"
            post "issues/delegate", to: "repositories#delegate_issue"
            post "issues/bulk", to: "repositories#bulk_issues"
            post :poll
            post :archive
            post :unarchive
            post :retry_failed_jobs
          end
        end
        post "repositories/:id/notes", to: "repositories#create_note", constraints: { id: /\d+/ }
        delete "repositories/:repository_id/notes/:id", to: "repositories#destroy_note", constraints: { repository_id: /\d+/, id: /\d+/ }
        get "repositories/:repository_id/documents", to: "repository_documents#index"
        post "repositories/:repository_id/documents", to: "repository_documents#create"
        delete "repository_documents/:id", to: "repository_documents#destroy"
        get "repositories/:repository_id/scheduled_tasks/new", to: "scheduled_tasks#new"
        get "repositories/:repository_id/scheduled_tasks", to: "scheduled_tasks#repository_index"
        post "repositories/:repository_id/scheduled_tasks", to: "scheduled_tasks#create"
        patch "repositories/:repository_id/scheduled_tasks/:id", to: "scheduled_tasks#repository_update"
        delete "repositories/:repository_id/scheduled_tasks/:id", to: "scheduled_tasks#repository_destroy"
        resources :scheduled_tasks, only: %i[ index show update destroy ] do
          member do
            post :pause
            post :resume
            post :fire_now
          end
        end

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
  get "repositories", to: "spa#show", as: :repositories
  post "repositories", to: "repositories#create"
  get "repositories/new", to: "spa#show", as: :new_repository
  get "repositories/new/legacy", to: "repositories#new", as: :legacy_new_repository
  get "repositories/legacy", to: "repositories#index", as: :legacy_repositories
  get "repositories/:id/edit", to: "spa#show", as: :edit_repository, constraints: { id: /\d+/ }
  get "repositories/:id/edit/legacy", to: "repositories#edit", as: :legacy_edit_repository, constraints: { id: /\d+/ }
  get "repositories/:id", to: "spa#show", as: :repository, constraints: { id: /\d+/ }
  get "repositories/:id/legacy", to: "repositories#show", as: :legacy_repository, constraints: { id: /\d+/ }
  resources :repositories, except: %i[ index create destroy new edit show ] do
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
    get "documents", to: "spa#show", as: :documents
    post "documents", to: "repositories/documents#create"
    get "documents/legacy", to: "repositories/documents#index", as: :legacy_documents
    post "documents/legacy", to: "repositories/documents#create"
    get "scheduled_tasks", to: "spa#show", as: :scheduled_tasks
    patch "scheduled_tasks/:id", to: "repositories/scheduled_tasks#update", as: :scheduled_task
    delete "scheduled_tasks/:id", to: "repositories/scheduled_tasks#destroy"
    get "scheduled_tasks/legacy", to: "repositories/scheduled_tasks#index", as: :legacy_scheduled_tasks
    patch "scheduled_tasks/legacy/:id", to: "repositories/scheduled_tasks#update", as: :legacy_scheduled_task
    delete "scheduled_tasks/legacy/:id", to: "repositories/scheduled_tasks#destroy"
    post "scheduled_tasks", to: "scheduled_tasks#create"
    get "scheduled_tasks/legacy/new", to: "scheduled_tasks#new", as: :legacy_new_scheduled_task
    post "scheduled_tasks/legacy", to: "scheduled_tasks#create"
  end
  delete "documents/:id", to: "repositories/documents#destroy", as: :document, constraints: { id: /\d+/ }
  get "repositories/:repository_id/scheduled_tasks/new", to: "spa#show", as: :new_repository_scheduled_task

  get "chats/new", to: "spa#show", as: :new_chat
  get "chats/new/legacy", to: "chats#new", as: :legacy_new_chat
  get "chats/:id", to: "spa#show", as: :chat, constraints: { id: /\d+/ }
  get "chats/:id/legacy", to: "chats#show", as: :legacy_chat, constraints: { id: /\d+/ }
  resources :chats, only: %i[ create ] do
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

  get "scheduled_tasks", to: "spa#show", as: :scheduled_tasks
  get "scheduled_tasks/:id", to: "spa#show", as: :scheduled_task, constraints: { id: /\d+/ }
  get "scheduled_tasks/:id/edit", to: "spa#show", as: :edit_scheduled_task, constraints: { id: /\d+/ }
  patch "scheduled_tasks/:id", to: "scheduled_tasks#update", constraints: { id: /\d+/ }
  delete "scheduled_tasks/:id", to: "scheduled_tasks#destroy", constraints: { id: /\d+/ }
  post "scheduled_tasks/:id/pause", to: "scheduled_tasks#pause", as: :pause_scheduled_task, constraints: { id: /\d+/ }
  post "scheduled_tasks/:id/resume", to: "scheduled_tasks#resume", as: :resume_scheduled_task, constraints: { id: /\d+/ }
  post "scheduled_tasks/:id/fire_now", to: "scheduled_tasks#fire_now", as: :fire_now_scheduled_task, constraints: { id: /\d+/ }
  get "scheduled_tasks/legacy", to: "scheduled_tasks#index", as: :legacy_scheduled_tasks
  get "scheduled_tasks/legacy/:id", to: "scheduled_tasks#show", as: :legacy_scheduled_task, constraints: { id: /\d+/ }
  get "scheduled_tasks/legacy/:id/edit", to: "scheduled_tasks#edit", as: :legacy_edit_scheduled_task, constraints: { id: /\d+/ }
  patch "scheduled_tasks/legacy/:id", to: "scheduled_tasks#update", constraints: { id: /\d+/ }
  delete "scheduled_tasks/legacy/:id", to: "scheduled_tasks#destroy", constraints: { id: /\d+/ }
  post "scheduled_tasks/legacy/:id/pause", to: "scheduled_tasks#pause", as: :legacy_pause_scheduled_task, constraints: { id: /\d+/ }
  post "scheduled_tasks/legacy/:id/resume", to: "scheduled_tasks#resume", as: :legacy_resume_scheduled_task, constraints: { id: /\d+/ }
  post "scheduled_tasks/legacy/:id/fire_now", to: "scheduled_tasks#fire_now", as: :legacy_fire_now_scheduled_task, constraints: { id: /\d+/ }
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
  get "epics/new", to: "spa#show", as: :new_epic
  get "epics/new/legacy", to: "epics#new", as: :legacy_new_epic
  get "epics/:id", to: "spa#show", as: :epic, constraints: { id: /\d+/ }
  get "epics/:id/legacy", to: "epics#show", as: :legacy_epic, constraints: { id: /\d+/ }
  get "epics/:id/edit", to: "spa#show", as: :edit_epic, constraints: { id: /\d+/ }
  get "epics/:id/edit/legacy", to: "epics#edit", as: :legacy_edit_epic, constraints: { id: /\d+/ }
  resources :epics, only: %i[ create update ] do
    member do
      patch :archive
      patch :state, action: :update_state
    end
  end
  get "smart_folders", to: "spa#show", as: :smart_folders
  post "smart_folders", to: "smart_folders#create"
  patch "smart_folders/:id", to: "smart_folders#update", as: :smart_folder, constraints: { id: /\d+/ }
  delete "smart_folders/:id", to: "smart_folders#destroy", constraints: { id: /\d+/ }
  get "smart_folders/legacy", to: "smart_folders#index", as: :legacy_smart_folders
  patch "smart_folders/legacy/:id", to: "smart_folders#update", as: :legacy_smart_folder, constraints: { id: /\d+/ }
  delete "smart_folders/legacy/:id", to: "smart_folders#destroy", constraints: { id: /\d+/ }
  get "tags", to: "spa#show", as: :tags
  post "tags", to: "tags#create"
  patch "tags/:id", to: "tags#update", as: :tag, constraints: { id: /\d+/ }
  delete "tags/:id", to: "tags#destroy", constraints: { id: /\d+/ }
  get "tags/legacy", to: "tags#index", as: :legacy_tags
  post "tags/legacy", to: "tags#create"
  patch "tags/legacy/:id", to: "tags#update", as: :legacy_tag, constraints: { id: /\d+/ }
  delete "tags/legacy/:id", to: "tags#destroy", constraints: { id: /\d+/ }
  get "cron_templates", to: "spa#show", as: :cron_templates
  post "cron_templates", to: "cron_templates#create"
  get "cron_templates/new", to: "spa#show", as: :new_cron_template
  get "cron_templates/:id", to: "spa#show", as: :cron_template, constraints: { id: /\d+/ }
  get "cron_templates/:id/edit", to: "spa#show", as: :edit_cron_template, constraints: { id: /\d+/ }
  patch "cron_templates/:id", to: "cron_templates#update", constraints: { id: /\d+/ }
  delete "cron_templates/:id", to: "cron_templates#destroy", constraints: { id: /\d+/ }
  get "cron_templates/legacy", to: "cron_templates#index", as: :legacy_cron_templates
  post "cron_templates/legacy", to: "cron_templates#create"
  get "cron_templates/legacy/new", to: "cron_templates#new", as: :legacy_new_cron_template
  get "cron_templates/legacy/:id", to: "cron_templates#show", as: :legacy_cron_template, constraints: { id: /\d+/ }
  get "cron_templates/legacy/:id/edit", to: "cron_templates#edit", as: :legacy_edit_cron_template, constraints: { id: /\d+/ }
  patch "cron_templates/legacy/:id", to: "cron_templates#update", constraints: { id: /\d+/ }
  delete "cron_templates/legacy/:id", to: "cron_templates#destroy", constraints: { id: /\d+/ }
  get "invitations", to: "spa#show", as: :invitations
  post "invitations", to: "invitations#create"
  delete "invitations/:id", to: "invitations#destroy", as: :invitation, constraints: { id: /\d+/ }
  get "invitations/legacy", to: "invitations#index", as: :legacy_invitations
  post "invitations/legacy", to: "invitations#create"
  delete "invitations/legacy/:id", to: "invitations#destroy", as: :legacy_invitation, constraints: { id: /\d+/ }
  # Legacy compatibility: the account menu's `/settings` entry is the
  # per-user credentials page. App-wide settings live at `/settings/edit`
  # and remain admin-only.
  get "settings", to: "spa#show"
  get "settings/edit", to: "spa#show", as: :edit_settings
  patch "settings", to: "settings#update"
  get "settings/edit/legacy", to: "settings#edit", as: :legacy_edit_settings
  patch "settings/legacy", to: "settings#update", as: :legacy_settings
  resources :bug_reports, only: %i[ create ]
  get "jobs/new", to: "spa#show", as: :new_job
  get "jobs/new/legacy", to: "jobs#new", as: :legacy_new_job
  post "jobs/legacy", to: "jobs#create", as: :legacy_jobs
  resources :jobs, only: %i[ show create ] do
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
