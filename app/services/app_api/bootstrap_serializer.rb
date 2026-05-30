module AppApi
  class BootstrapSerializer
    GITHUB_REPO = "tkadauke/syrus".freeze

    def initialize(user:, csrf_token:)
      @user = user
      @csrf_token = csrf_token
    end

    def as_json(*)
      {
        current_user: user_payload,
        app: app_payload,
        csrf_token: @csrf_token,
        feature_flags: {
          migrated_routes: []
        }
      }
    end

    private

    attr_reader :user

    def user_payload
      {
        id: user.id,
        email_address: user.email_address,
        name: user.name,
        display_name: user.display_name,
        admin: user.admin?,
        scheduling_paused: user.scheduling_paused,
        landing_paused: user.landing_paused,
        agent_provider: user.agent_provider,
        agent_max_turns: user.agent_max_turns
      }
    end

    def app_payload
      {
        revision: app_revision,
        revision_url: app_revision_url
      }
    end

    def app_revision
      ENV["GIT_SHA"].presence || "dev"
    end

    def app_revision_url
      return nil if app_revision == "dev"

      "https://github.com/#{GITHUB_REPO}/commit/#{app_revision}"
    end
  end
end
