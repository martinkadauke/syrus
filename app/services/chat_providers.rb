module ChatProviders
  class ConfigurationError < StandardError; end

  def self.for(provider)
    provider_key = provider.to_s
    klass = PerformanceLogging.phase("chat_providers.lookup", provider: provider_key) do
      Syrus::PluginRegistry.providers_for(:chat_provider)
        .find do |p|
          PerformanceLogging.plugin_call(extension_point: :chat_provider, provider: p, operation: :provider_key) do
            p.provider_key == provider_key
          end
        end
    end
    unless klass
      raise ConfigurationError, "Unknown chat provider: #{provider.inspect}"
    end

    klass
  end

  def self.provider_keys
    Syrus::PluginRegistry.providers_for(:chat_provider).map(&:provider_key)
  end

  def self.display_name(provider)
    self.for(provider).display_name
  rescue ConfigurationError
    provider.to_s.titleize
  end
end
