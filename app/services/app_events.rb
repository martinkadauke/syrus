class AppEvents
  def self.broadcast(user:, type:, resource:, id: nil, changed: [], payload: nil, occurred_at: Time.current)
    event = {
      type: type.to_s,
      resource: resource.to_s,
      id: id,
      changed: Array(changed).map(&:to_s),
      occurred_at: occurred_at.iso8601(3)
    }
    event[:payload] = payload if payload

    AppUserChannel.broadcast_to(user, event.as_json)
  end
end
