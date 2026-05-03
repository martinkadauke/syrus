class CredentialsController < ApplicationController
  def edit
    @user = Current.user
  end

  def update
    attrs = credentials_params.to_h.reject { |_, v| v.blank? }
    if Current.user.update(attrs)
      redirect_to edit_credentials_path, notice: "Credentials updated."
    else
      @user = Current.user
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def credentials_params
    params.expect(user: [ :claude_oauth_token, :github_token, :agent_max_turns ])
  end
end
