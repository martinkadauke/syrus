class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :compute_system_alerts
  helper_method :default_chat_path

  private

  # Populate the layout's alert banner area. Computed every request
  # rather than cached — alert sources are cheap (column reads) and
  # we want the banner to disappear the moment the operator fixes
  # the underlying problem (e.g. updates their GH token).
  def compute_system_alerts
    @system_alerts = SystemAlerts.active_for(user: Current.user)
  end

  def require_admin
    return if Current.user&.admin?
    redirect_to root_path, alert: "Admin access required."
  end

  def default_chat_path
    return new_session_path unless Current.user

    chat_session = Current.user.chat_sessions
      .order(Arel.sql("last_message_at IS NULL ASC"), last_message_at: :desc, created_at: :desc, id: :desc)
      .first

    chat_session ? chat_path(chat_session) : new_chat_path
  end

  # Run a block with a short MySQL innodb_lock_wait_timeout (default
  # 50s) so a request-path transaction blocked on FK / gap-lock
  # contention fails fast and bounces to a retry / friendly error
  # instead of hanging the worker for ~50s. Resets to the connection
  # default in `ensure` so connection-pool reuse doesn't propagate
  # the short timeout to unrelated requests.
  #
  # No-op on SQLite (dev/test) — the setting is MySQL-specific.
  def with_short_lock_wait(seconds = 5)
    connection = ActiveRecord::Base.connection
    return yield unless connection.adapter_name.downcase.include?("mysql")

    connection.execute("SET innodb_lock_wait_timeout = #{seconds.to_i}")
    begin
      yield
    ensure
      begin
        connection.execute("SET innodb_lock_wait_timeout = DEFAULT")
      rescue StandardError => e
        Rails.logger.warn("[with_short_lock_wait] failed to reset timeout: #{e.class}: #{e.message}")
      end
    end
  end
end
