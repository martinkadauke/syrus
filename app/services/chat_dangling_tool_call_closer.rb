require "set"

class ChatDanglingToolCallCloser
  DEFAULT_MESSAGE = "Agent turn ended before this tool returned."

  def self.close!(...)
    new(...).close!
  end

  def initialize(chat_session:, message: DEFAULT_MESSAGE)
    @chat_session = chat_session
    @message = message.to_s.presence || DEFAULT_MESSAGE
  end

  def close!
    tool_uses = tool_uses_after_latest_user.to_a
    return 0 if tool_uses.empty?

    answered_ids = Set.new(
      messages_after_latest_user
        .where(role: "tool_result", tool_use_id: tool_uses.filter_map(&:tool_use_id))
        .pluck(:tool_use_id)
        .map(&:to_s)
    )

    tool_uses.sum do |tool_use|
      next 0 if tool_use.tool_use_id.present? && answered_ids.include?(tool_use.tool_use_id.to_s)

      @chat_session.messages.create!(
        role: "tool_result",
        tool_name: tool_use.tool_name,
        tool_use_id: tool_use.tool_use_id,
        content: {
          "type" => "tool_result",
          "tool_use_id" => tool_use.tool_use_id.to_s,
          "content" => [ { "type" => "text", "text" => @message } ],
          "is_error" => true
        }
      )
      1
    end
  end

  private

  def tool_uses_after_latest_user
    messages_after_latest_user.where(role: "tool_use").order(:created_at, :id)
  end

  def messages_after_latest_user
    return @messages_after_latest_user if defined?(@messages_after_latest_user)

    latest_user = @chat_session.messages.where(role: "user").order(:created_at, :id).last
    scope = @chat_session.messages
    @messages_after_latest_user = if latest_user
      scope.where(
        "created_at > ? OR (created_at = ? AND id > ?)",
        latest_user.created_at,
        latest_user.created_at,
        latest_user.id
      )
    else
      scope.none
    end
  end
end
