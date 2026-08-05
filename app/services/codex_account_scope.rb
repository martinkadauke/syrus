require "base64"
require "json"

class CodexAccountScope
  def self.for_user(user)
    new(user).account_id
  end

  def initialize(user)
    @user = user
  end

  def account_id
    auth = JSON.parse(@user.codex_auth_json.to_s)
    auth.dig("tokens", "account_id").presence ||
      token_claim(auth, "chatgpt_account_id").presence ||
      jwt_claim(id_token(auth), [ "https://api.openai.com/auth", "chatgpt_account_id" ])
  rescue JSON::ParserError
    nil
  end

  private

  def id_token(auth)
    auth.dig("tokens", "id_token")
  end

  def token_claim(auth, key)
    token = id_token(auth)
    token[key] if token.is_a?(Hash)
  end

  def jwt_claim(jwt, path)
    return unless jwt.is_a?(String)

    _header, payload, _signature = jwt.split(".", 3)
    return if payload.blank?

    decoded = Base64.urlsafe_decode64(payload.ljust((payload.length + 3) / 4 * 4, "="))
    path.reduce(JSON.parse(decoded)) { |memo, key| memo.is_a?(Hash) ? memo[key] : nil }
  rescue ArgumentError, JSON::ParserError
    nil
  end
end
