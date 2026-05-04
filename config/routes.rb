Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resources :users, only: %i[ new create ]

  resource :credentials, only: %i[ edit update ] do
    post :rotate_api_token
    delete :revoke_api_token
  end

  # Admin REST API. Token-based auth (per-user), JSON only.
  # See docs/plans/admin-diagnostics.md for the endpoint plan.
  namespace :api do
    namespace :v1 do
      namespace :admin do
        resources :jobs, only: %i[ show ]
      end
    end
  end
  resources :repositories do
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
    end
    resources :scheduled_tasks, only: %i[ new create ]
  end

  resources :scheduled_tasks, only: %i[ index show edit update destroy ] do
    member do
      post :pause
      post :resume
      post :fire_now    # manually fire an active task without waiting for cron
    end
  end
  resources :invitations, only: %i[ index create destroy ]
  resource :settings, only: %i[ show edit update ]
  resources :jobs, only: %i[ show ] do
    member do
      post :run_again      # soft replay — new Run on the existing branch
      post :restart        # hard reset — close this thread, open a new one with a fresh branch + PR
      post :cancel         # cancel active runs + close the thread
      post :reopen         # undo a close — closed → open, polling resumes
      post :poll_feedback  # manually trigger PollPullRequestJob for this Job
      post :rebase         # manually trigger a rebase Run on this Job's PR
      post :check_mergeability  # ask GitHub for the latest mergeable status now
      post :resume         # continue a failed Run via claude --resume
      post :stop_run       # cancel a single active Run without closing the thread
      post :retry_step     # re-run the failed step in a failed Workflow (keeps the existing workspace)
    end
  end

  namespace :admin do
    # System overview — landing page for the admin area.
    # See docs/plans/admin-diagnostics.md (F).
    root to: "overview#show"

    # Per-Run claude transcript viewer — renders the captured
    # ClaudeSession.transcript_jsonl as a structured event stream.
    # See docs/plans/admin-diagnostics.md (A).
    get  "runs/:run_id/transcript",          to: "transcripts#show",     as: :run_transcript
    get  "runs/:run_id/transcript/download", to: "transcripts#download", as: :run_transcript_download

    # SolidQueue inspector — see docs/plans/admin-diagnostics.md (B).
    get  "queue",                  to: "queue#index", as: :queue_root
    get  "queue/:tab",             to: "queue#show",            as: :queue, constraints: { tab: /active|pending|failed|recurring|workers/ }
    post "queue/reap_stale_runs",  to: "queue#reap_stale_runs", as: :reap_stale_runs

    # Stuck-things watchlist — Run heartbeat stale or Workflow
    # nearing prune. See Admin::StuckItems for the definition.
    get "stuck", to: "stuck#index", as: :stuck
  end

  root "home#index"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
