module PendingActions
  REGISTRY = {}

  def self.for(action_key)
    key = action_key.to_s

    return REGISTRY[key] if REGISTRY.key?(key)

    begin
      const_get(key.camelize, false)
    rescue NameError
      # fall through to the explicit unknown-action error below
    end

    REGISTRY.fetch(key) { raise UnknownAction, "unknown pending action: #{action_key}" }
  end

  def self.register(klass)
    REGISTRY[klass.action_key] = klass
  end

  UnknownAction = Class.new(StandardError)
end
