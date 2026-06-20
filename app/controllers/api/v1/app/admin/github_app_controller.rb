module Api
  module V1
    module App
      module Admin
        class GithubAppController < BaseController
          GITHUB_MANIFEST_URL = "https://github.com/settings/apps/new".freeze

          def register
            state = SecureRandom.urlsafe_base64(24)
            session[:github_app_manifest_state] = state
            # Remember where registration was started so the GitHub callback can
            # land on a minimal "you can close this" page during onboarding
            # instead of the full admin confirmation page.
            session[:github_app_manifest_origin] = params[:origin].to_s.presence

            render json: status_payload.merge(
              github_manifest_url: "#{GITHUB_MANIFEST_URL}?state=#{CGI.escape(state)}",
              manifest: GithubAppManifest.new(
                user: Current.user,
                callback_url: admin_github_app_callback_url
              ).to_json,
              submit_label: AppSetting.github_app_registered? ? "Re-register GitHub App" : "Register GitHub App"
            )
          end

          def confirm
            render json: status_payload
          end

          private

          def status_payload
            setting = AppSetting.current

            {
              github_app: {
                registered: setting.github_app_registered?,
                id: setting.github_app_id,
                slug: setting.github_app_slug,
                registered_at: setting.github_app_registered_at&.iso8601,
                install_url: ::App::Presentation.github_app_generic_install_url
              }
            }
          end
        end
      end
    end
  end
end
