module Syrus
  module Plugin
    # Interface module for interactive chat provider implementations.
    #
    # Include this module in any class registered as a :chat_provider
    # extension point. The class must implement:
    #
    #   .provider_key   -> String  - unique stable identifier (e.g. "claude")
    #   .display_name   -> String  - shown in the settings UI
    #   .available?     -> bool    - true when the provider is usable
    #   #invoke(...)     -> Agent result for one chat turn
    #
    # Chat providers are instantiated by the host ChatProviders facade with:
    #
    #   new(chat:, runner:, image_paths:, file_paths:, env:)
    #
    # and should implement the invocation/session-capture contract inherited
    # from ChatProviders::Base.
    module ChatProvider
    end
  end
end
