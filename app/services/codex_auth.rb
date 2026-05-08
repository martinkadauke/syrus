require "fileutils"
require "open3"

class CodexAuth
  class Error < AgentProviders::ConfigurationError; end

  Result = Data.define(:api_key)

  CODEX_ENV_FORWARD = CodexInvocation::CODEX_ENV_FORWARD

  def initialize(user:, codex_home:, runner: nil)
    @user = user
    @codex_home = codex_home.to_s
    @runner = runner || method(:default_runner)
  end

  def prepare!
    case @user.codex_auth_mode
    when "api_key"
      prepare_api_key
    when "chatgpt_login"
      prepare_chatgpt_login
    else
      raise Error, "Unknown Codex auth mode: #{@user.codex_auth_mode.inspect}"
    end
  end

  private

  def prepare_api_key
    raise Error, "Codex API key is not configured" if @user.codex_api_key.blank?

    Result.new(api_key: @user.codex_api_key)
  end

  def prepare_chatgpt_login
    raise Error, "Codex access token is not configured" if @user.codex_access_token.blank?

    FileUtils.mkdir_p(@codex_home)
    @runner.call(codex_home: @codex_home, access_token: @user.codex_access_token)
    Result.new(api_key: nil)
  end

  def default_runner(codex_home:, access_token:)
    env = codex_env(codex_home)
    output, status = Open3.capture2e(
      env,
      "codex", "login", "--with-access-token",
      stdin_data: "#{access_token}\n",
      unsetenv_others: true
    )
    return if status.success?

    raise Error, "Codex ChatGPT login failed: #{sanitize_output(output, access_token)}"
  end

  def codex_env(codex_home)
    ENV.slice(*CODEX_ENV_FORWARD).merge("CODEX_HOME" => codex_home)
  end

  def sanitize_output(output, access_token)
    text = output.to_s.strip
    text = "codex login exited non-zero" if text.blank?
    text.gsub(access_token.to_s, "[redacted]")
  end
end
