module PlatformDelivery
  class BaseAdapter
    def deliver(message:, platform_identity:) = raise NotImplementedError
  end
end
