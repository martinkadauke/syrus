class CredentialsController < ApplicationController
  helper_method :credentials_form_path,
                :credentials_rotate_api_token_path,
                :credentials_revoke_api_token_path

  def edit
    @user = Current.user
    # Show the freshly-minted token to the operator ONCE — flash
    # carries it across the post-create redirect, then it's gone.
    @new_api_token = flash[:new_api_token]
  end

  def update
    if params[:clear_credential].present?
      clear_credential(params[:clear_credential])
      return
    end

    attrs = credentials_params.to_h.reject { |_, v| v.blank? }
    if Current.user.update(attrs)
      redirect_to credentials_redirect_path, notice: "Credentials updated."
    else
      @user = Current.user
      render :edit, status: :unprocessable_content
    end
  end

  # Admin-only: rotate (or first-time generate) the API token. We
  # store it deterministic-encrypted and never display it again,
  # so the operator must record it on this round-trip or rotate.
  def rotate_api_token
    unless Current.user.admin?
      redirect_to credentials_redirect_path, alert: "API token is admin-only." and return
    end
    flash[:new_api_token] = Current.user.generate_api_token!
    redirect_to credentials_redirect_path, notice: "API token rotated. Copy it now — it won't be shown again."
  end

  def revoke_api_token
    unless Current.user.admin?
      redirect_to credentials_redirect_path, alert: "API token is admin-only." and return
    end
    Current.user.revoke_api_token!
    redirect_to credentials_redirect_path, notice: "API token revoked."
  end

  private

  def clear_credential(credential)
    label = User::CLEARABLE_CREDENTIALS[credential.to_s]
    redirect_to credentials_redirect_path, alert: "Unknown credential." and return unless label

    Current.user.clear_credential!(credential)
    redirect_to credentials_redirect_path, notice: "#{label} cleared."
  end

  def credentials_params
    params.expect(user: [ :name, :github_handle, :agent_provider, :claude_oauth_token, :codex_auth_mode,
                          :codex_api_key, :codex_auth_json, :github_token,
                          :agent_max_turns, :scheduling_paused, :auto_approve_mode ])
  end

  def credentials_form_path
    legacy_credentials_request? ? legacy_credentials_path : credentials_path
  end

  def credentials_rotate_api_token_path
    legacy_credentials_request? ? legacy_rotate_api_token_credentials_path : rotate_api_token_credentials_path
  end

  def credentials_revoke_api_token_path
    legacy_credentials_request? ? legacy_revoke_api_token_credentials_path : revoke_api_token_credentials_path
  end

  def credentials_redirect_path
    legacy_credentials_request? ? legacy_edit_credentials_path : edit_credentials_path
  end

  def legacy_credentials_request?
    request.path.start_with?("/credentials/legacy") || request.path.start_with?("/credentials/edit/legacy")
  end
end
