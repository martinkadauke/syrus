module Oauth
  # Receives the Claude subscription OAuth redirect (loopback / same-host
  # flow), exchanges the code for a long-lived token, saves it on the current
  # user, then renders a tiny page that reports the result back to the opener
  # window and closes itself.
  class ClaudeController < ApplicationController
    def callback
      stash = session.delete("claude_oauth") || session.delete(:claude_oauth) || {}

      if params[:error].present?
        return render_result(ok: false, message: params[:error_description].presence || "Authorization was denied.")
      end

      if stash["state"].blank? || params[:state].to_s != stash["state"].to_s
        return render_result(ok: false, message: "The authorization response did not match this session. Try again.")
      end

      token = ClaudeOauth.exchange(
        code: params[:code].to_s,
        verifier: stash["verifier"],
        state: stash["state"],
        redirect_uri: stash["redirect_uri"]
      )
      Current.user.update!(claude_oauth_token: token)

      probe = CredentialProbe.call(user: Current.user, credential: "claude_oauth_token")
      render_result(ok: probe.ok, message: probe.message)
    rescue ClaudeOauth::Error => e
      render_result(ok: false, message: e.message)
    end

    private

    def render_result(ok:, message:)
      @ok = ok
      @message = message
      render "oauth/claude/callback", layout: false
    end
  end
end
