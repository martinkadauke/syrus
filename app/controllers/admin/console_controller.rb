module Admin
  # Operator console — the kill-switch panel. Each action is one
  # button + a confirm dialog, logs an AdminAction row for after-
  # the-fact accountability, then redirects back to the console
  # so the operator sees the new state immediately.
  #
  # See docs/plans/complete/admin-diagnostics.md (L).
  class ConsoleController < BaseController
    def show
      @settings = AppSetting.current
      @recent_actions = AdminAction.recent.includes(:user)
      @users = User.order(:email_address).to_a
    end

    def pause_polling
      AppSetting.current.update!(polling_paused: true)
      log_action(:pause_polling)
      redirect_to admin_console_path, notice: "Polling paused. Recurring fan-out jobs will short-circuit on each tick."
    end

    def unpause_polling
      AppSetting.current.update!(polling_paused: false)
      log_action(:unpause_polling)
      redirect_to admin_console_path, notice: "Polling resumed."
    end

    def pause_runs
      AppSetting.current.update!(runs_paused: true)
      log_action(:pause_runs)
      redirect_to admin_console_path, notice: "RunJobs paused. New attempts re-enqueue themselves until unpaused."
    end

    def unpause_runs
      AppSetting.current.update!(runs_paused: false)
      log_action(:unpause_runs)
      redirect_to admin_console_path, notice: "RunJobs resumed."
    end

    def clear_github_cache
      user_id = params[:user_id].presence
      pattern, summary = if user_id
        scope_user = User.find(user_id)
        [ "github_etag/u#{scope_user.id}/*", "for #{scope_user.email_address}" ]
      else
        [ "github_etag/*", "for all users" ]
      end

      cleared = clear_cache_pattern(pattern)
      log_action(:clear_github_cache, scope: pattern, cleared_count: cleared)
      redirect_to admin_console_path, notice: "Cleared #{cleared} GitHub cache entries #{summary}."
    end

    private

    def log_action(action, **params)
      AdminAction.log!(user: Current.user, action: action, params: params)
    end

    # Wrap delete_matched in a rescue — not every Rails.cache backend
    # supports it. SolidCache (the production backend) does; the
    # in-memory test backend returns an integer count, which is what
    # we want.
    def clear_cache_pattern(pattern)
      Rails.cache.delete_matched(pattern)
    rescue NotImplementedError, StandardError => e
      # NotImplementedError is what some cache adapters raise when
      # delete_matched isn't supported (rescued separately because
      # it doesn't descend from StandardError).
      Rails.logger.warn("[Admin::Console] cache clear failed: #{e.class}: #{e.message}")
      0
    end
  end
end
