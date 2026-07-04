module Api
  module V1
    module App
      module Admin
        class GithubAppController < BaseController
          def register
            state = GithubAppManifestState.generate(user: Current.user, origin: params[:origin].to_s.presence)

            # The registration itself happens in the user's default browser via
            # the tokenized bounce page — never in an embedded window, where the
            # user typically has no GitHub login. `syrus_external=1` tells the
            # desktop shell to hand the URL to the OS browser.
            render json: status_payload.merge(
              bounce_url: admin_github_app_manifest_url(state: state, syrus_external: 1),
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
