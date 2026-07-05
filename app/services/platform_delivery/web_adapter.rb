module PlatformDelivery
  # ActionCable broadcasts from ChatMessage already handle web delivery.
  class WebAdapter < BaseAdapter
    def deliver(message:, platform_identity:) = nil
  end
end
