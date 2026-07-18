# Chat-provider helpers extracted from Api::V1::App::ChatsController.
#
# These normalize the requested chat-provider param, humanize a provider slug,
# and build the provider picker options (Default + one per configured
# provider) for a chat session. `chat_provider_options` reads the current
# user's configured providers, so it mixes back in unchanged. Kept private on
# include.
module ChatProviderOptions
  private

  def normalized_chat_provider_param(value)
    value.to_s.strip.presence
  end

  def chat_provider_label(provider)
    case provider
    when "claude" then "Claude"
    when "codex" then "Codex"
    else provider.to_s.titleize
    end
  end

  def chat_provider_options(chat_session)
    configured = Current.user.configured_agent_providers
    [
      {
        value: nil,
        label: "Default",
        configured: Current.user.chat_provider_configured?(chat_session.user.effective_chat_provider),
        effective_provider: chat_session.user.effective_chat_provider,
        effective_label: chat_provider_label(chat_session.user.effective_chat_provider)
      }
    ] + User::CHAT_PROVIDERS.map do |provider|
      {
        value: provider,
        label: chat_provider_label(provider),
        configured: configured.include?(provider),
        effective_provider: provider,
        effective_label: chat_provider_label(provider)
      }
    end
  end
end
