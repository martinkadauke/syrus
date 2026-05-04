# Surface "something is broken right now, here's what to do about it"
# banners at the top of every authenticated page. Designed for many
# alert sources to compose into one rendering path:
#
#   * per-user computed (GitHub token blocked, Claude OAuth missing)
#   * global computed (polling paused, runs paused via AppSetting)
#   * future: stored alerts (a `system_alerts` table) for things
#     that should persist across pod restarts and need explicit
#     dismissal.
#
# Add a new alert source by writing a private method here that
# returns a `SystemAlerts::Alert` (or nil) and calling it from
# `.active_for`. The view layer doesn't change — the
# `shared/_alert_banner` partial renders any Alert by its severity,
# title, message, and action_steps.
module SystemAlerts
  Alert = Data.define(:id, :severity, :title, :message, :action_steps, :cta) do
    # Severity drives color in the banner partial:
    #   :alarm — red, "this is broken right now"
    #   :warn  — amber, "this is degraded but limping"
    #   :info  — blue, "you should know about this"
    SEVERITIES = %i[ alarm warn info ].freeze
  end

  def self.active_for(user:)
    out = []
    out << github_token_blocked(user) if user&.gh_api_blocked?
    out
  end

  def self.github_token_blocked(user)
    Alert.new(
      id: "github_token_scope:#{user.id}",
      severity: :alarm,
      title: "GitHub API access is blocked for this account.",
      message: "Syrus tried to read GitHub on your behalf and got back: " \
               "#{user.gh_api_blocked_reason}. PR-feedback polling and " \
               "CI-failure detection are degraded until this is fixed; " \
               "the banner clears automatically on the next successful API call.",
      action_steps: [
        "Open https://github.com/settings/tokens (classic) or the fine-grained tokens page.",
        "Either: classic PAT with the <code>repo</code> scope, " \
          "or: fine-grained PAT with <code>Pull requests: read</code> AND <code>Checks: read</code>.",
        "Paste the new token into <a class=\"underline\" href=\"/credentials/edit\">Settings → Credentials</a> and save."
      ],
      cta: { text: "Update token", path: "/credentials/edit" }
    )
  end
  private_class_method :github_token_blocked
end
