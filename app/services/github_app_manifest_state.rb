
# Signed, self-contained state for the GitHub App manifest flow.
#
# The desktop app hands the registration flow to the user's default browser
# (the embedded window has no GitHub login, and shell.openExternal cannot
# carry a POST body), so the state GitHub echoes back to the callback must be
# verifiable WITHOUT the operator's Syrus session cookie. The token embeds
# everything the callback needs: the registering user, the origin surface,
# and a nonce for one-shot consumption.
class GithubAppManifestState
  TTL = 15.minutes
  PURPOSE = "github_app_manifest".freeze

  Payload = Struct.new(:user_id, :origin, :nonce, keyword_init: true)

  def self.generate(user:, origin: nil)
    verifier.generate(
      { "user_id" => user.id, "origin" => origin.presence, "nonce" => SecureRandom.urlsafe_base64(16) },
      purpose: PURPOSE,
      expires_in: TTL
    )
  end

  # Returns a Payload, or nil for a forged, malformed, or expired token.
  def self.verify(token)
    data = verifier.verified(token.to_s, purpose: PURPOSE)
    return nil unless data.is_a?(Hash) && data["user_id"].present? && data["nonce"].present?

    Payload.new(user_id: data["user_id"], origin: data["origin"], nonce: data["nonce"])
  end

  # One-shot guard: the first caller wins, replays within the TTL lose.
  # Backed by Rails.cache (Solid Cache in production); a null cache degrades
  # to signature+TTL protection only.
  def self.consume!(nonce)
    Rails.cache.write("github_app_manifest_state:#{nonce}", 1, unless_exist: true, expires_in: TTL)
  end

  def self.verifier
    Rails.application.message_verifier(PURPOSE)
  end
  private_class_method :verifier
end
