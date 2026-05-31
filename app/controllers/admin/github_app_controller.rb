module Admin
  class GithubAppController < BaseController
    def callback
      return redirect_to admin_github_app_register_path, alert: "GitHub App registration state did not match." unless valid_state?

      code = params[:code].to_s
      return redirect_to admin_github_app_register_path, alert: "GitHub did not return a manifest code." if code.blank?

      payload = GithubAppClient.manifest_conversion(code)
      persist_app_credentials!(payload)
      SyncInstallationsJob.perform_later(Current.user.id)
      redirect_to admin_github_app_confirm_path, notice: "GitHub App registered."
    rescue Octokit::Error, Faraday::Error, JSON::ParserError => e
      redirect_to admin_github_app_register_path, alert: "GitHub App registration failed: #{e.message}"
    ensure
      session.delete(:github_app_manifest_state)
    end

    private

    def valid_state?
      session[:github_app_manifest_state].present? && ActiveSupport::SecurityUtils.secure_compare(
        session[:github_app_manifest_state],
        params[:state].to_s
      )
    end

    def persist_app_credentials!(payload)
      AppSetting.current.update!(
        github_app_id: payload.fetch("id"),
        github_app_slug: payload["slug"],
        github_app_private_key_pem: payload.fetch("pem"),
        github_app_registered_at: Time.current
      )
    end
  end
end
