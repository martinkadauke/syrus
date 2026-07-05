module PlatformDelivery
  class Registry
    ADAPTERS = {
      "web" => WebAdapter,
      "telegram" => TelegramAdapter
    }.freeze

    @runtime_adapters = {}

    class << self
      def register(platform, adapter_class)
        @runtime_adapters = @runtime_adapters.merge(platform.to_s => adapter_class)
      end

      def for(platform)
        adapter_class = adapter_class_for(platform) || BaseAdapter
        adapter_class.new
      end

      def registered?(platform)
        adapter_class_for(platform).present?
      end

      private

      def adapter_class_for(platform)
        @runtime_adapters[platform.to_s] || ADAPTERS[platform.to_s]
      end
    end
  end
end
