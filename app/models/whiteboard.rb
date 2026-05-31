class Whiteboard < ApplicationRecord
  MAX_ELEMENTS = 1000
  ELEMENT_LIMIT_MESSAGE = "Whiteboard at element limit (1000). Operator must clear or remove some shapes before adding more."

  belongs_to :chat_session

  # MySQL 8 doesn't allow defaults on JSON columns, so we seed an
  # empty scene on initialize. Existing rows keep whatever they had
  # serialized previously.
  after_initialize :seed_empty_scene_json, if: :new_record?

  validates :version, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :scene_json_has_elements_array
  validate :scene_json_within_element_limit

  def self.default_state
    { "elements" => [], "version" => 0 }
  end

  def current_state
    {
      "elements" => scene_json.fetch("elements"),
      "version" => version
    }
  end

  def elements
    scene_json.fetch("elements")
  end

  def replace_elements!(elements)
    raise ArgumentError, self.class.element_limit_message if elements.size > MAX_ELEMENTS

    update!(
      scene_json: { "elements" => elements },
      version: version + 1,
      last_edited_at: Time.current
    )
    broadcast_scene
  end

  # Replace the small `data-whiteboard-target="broadcast"` element on the
  # chat page so the next render's data-version + data-elements-json
  # carry the new state. The Stimulus controller's
  # `broadcastTargetConnected` reads those dataset values and applies
  # them via Excalidraw's programmatic API. Target id matches what the
  # view renders for the chat session.
  def broadcast_scene
    Turbo::StreamsChannel.broadcast_replace_later_to(
      broadcast_channel,
      target: "chat_session_#{chat_session_id}_whiteboard_broadcast",
      partial: "chats/whiteboard_broadcast",
      locals: { chat_session: chat_session, whiteboard: self }
    )
    AppEvents.broadcast(
      user: chat_session.user,
      type: "updated",
      resource: "chat",
      id: chat_session_id,
      changed: [ "whiteboard" ],
      payload: current_state
    )
  end

  def broadcast_channel
    "chat_session_#{chat_session_id}_whiteboard"
  end

  def self.element_limit_message
    ELEMENT_LIMIT_MESSAGE
  end

  private

  def seed_empty_scene_json
    self.scene_json ||= { "elements" => [] }
  end

  def scene_json_has_elements_array
    unless scene_json.is_a?(Hash)
      errors.add(:scene_json, "must be a hash")
      return
    end

    errors.add(:scene_json, "must include an elements array") unless scene_json["elements"].is_a?(Array)
  end

  def scene_json_within_element_limit
    return unless scene_json.is_a?(Hash) && scene_json["elements"].is_a?(Array)

    errors.add(:scene_json, self.class.element_limit_message) if scene_json["elements"].size > MAX_ELEMENTS
  end
end
