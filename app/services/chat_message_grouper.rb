module ChatMessageGrouper
  ABBREV_USE_PREFIX = "● ".freeze
  ABBREV_RESULT_PREFIX = "  ⎿ ".freeze
  ABBREV_USE_PATTERN = /\A●\s+(\S+?)(?:\((.*)\))?\s*\z/m.freeze

  module_function

  # Wrap a single abbreviated tool_use message in the same shape the
  # initial-render grouper produces, so a Turbo Stream append of one
  # message can reuse the tool_call_group partial.
  def single_call_group(message)
    tool, detail = parse_tool_signature(message)
    { type: :tool_group, tool: tool, calls: [ { message: message, detail: detail } ] }
  end

  # Walks a chronological array of ChatMessage records and returns a
  # flat list of "items" for the chat view. Most messages pass through
  # as `{ type: :message, message: <ChatMessage> }`; consecutive
  # abbreviated tool_use messages of the same tool name collapse into
  # `{ type: :tool_group, tool: "Read", calls: [...] }` where each
  # call carries its own use message and (optionally) the result that
  # immediately followed it. Abbreviated tool_result messages don't
  # appear as standalone items — they're attached to the preceding
  # tool_use call's `:result`. Structured/canvas tool_use messages
  # (those without the "● <Tool>(…)" abbreviation marker) still pass
  # through individually so their proposal/whiteboard cards keep
  # working.
  def group(messages)
    items = []
    current_group = nil

    messages.each do |message|
      if abbreviated_tool_use?(message)
        tool, detail = parse_tool_signature(message)
        call = { message: message, detail: detail }

        if current_group && current_group[:tool] == tool
          current_group[:calls] << call
        else
          current_group = { type: :tool_group, tool: tool, calls: [ call ] }
          items << current_group
        end
      elsif abbreviated_tool_result?(message)
        if current_group && current_group[:calls].any? && current_group[:calls].last[:result].nil?
          current_group[:calls].last[:result] = message
        else
          items << { type: :message, message: message }
          current_group = nil
        end
      else
        current_group = nil
        items << { type: :message, message: message }
      end
    end

    items
  end

  def abbreviated_tool_use?(message)
    message.role == "tool_use" && abbreviated_text(message)&.start_with?(ABBREV_USE_PREFIX)
  end

  def abbreviated_tool_result?(message)
    message.role == "tool_result" && abbreviated_text(message)&.start_with?(ABBREV_RESULT_PREFIX)
  end

  def parse_tool_signature(message)
    text = abbreviated_text(message).to_s
    if (match = text.match(ABBREV_USE_PATTERN))
      [ match[1], match[2].to_s ]
    else
      [ message.tool_name.presence || "tool", text.sub(ABBREV_USE_PREFIX, "") ]
    end
  end

  def abbreviated_text(message)
    return nil unless message.content.is_a?(Hash)

    text = message.content["text"]
    text if text.is_a?(String)
  end
end
