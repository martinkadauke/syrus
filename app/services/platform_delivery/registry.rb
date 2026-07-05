module PlatformDelivery
  class Registry
    ADAPTERS = {
      "web" => WebAdapter
      # "telegram" => TelegramAdapter  # registered when TelegramPollingJob loads
    }.freeze

    @runtime_adapters = {}

    class << self
      def register(platform, adapter_class)
        @runtime_adapters = @runtime_adapters.merge(platform.to_s => adapter_class)
      end

      def for(platform)
        adapter_class = @runtime_adapters[platform.to_s] || ADAPTERS[platform.to_s] || BaseAdapter
        adapter_class.new
      end
    end
  end
end
