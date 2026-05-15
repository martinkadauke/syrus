module SyrusChatMcp
  module Canvas
    class ElementLimitExceeded < StandardError; end

    SHAPE_TYPES = %w[rectangle ellipse diamond sticky].freeze
    ELEMENT_TYPES = (SHAPE_TYPES + %w[text arrow]).freeze
    DEFAULT_COLOR = "#f8fafc"
    DEFAULT_STROKE = "#1f2937"

    module_function

    def read(chat_session)
      whiteboard = chat_session.whiteboard
      return { version: 0, elements: [] } unless whiteboard

      { version: whiteboard.version, elements: whiteboard.elements }
    end

    def mutate(chat_session, tool_name, args)
      whiteboard = nil
      result = nil

      Whiteboard.transaction do
        whiteboard = find_or_create_whiteboard(chat_session).lock!
        elements = deep_dup_elements(whiteboard.elements)
        result = yield(elements)
        ensure_within_element_limit!(elements)

        whiteboard.scene_json = { "elements" => elements }
        whiteboard.version += 1
        whiteboard.last_edited_at = Time.current
        whiteboard.save!
      end

      # We deliberately do NOT persist a parallel structured tool_use
      # row here. The agent's stream-json log_sink already creates an
      # abbreviated tool_use ("● draw_shape(rectangle)") for every MCP
      # invocation. Persisting a second row was duplicate bookkeeping
      # that produced two entries per draw_shape in the chat UI.

      whiteboard.broadcast_scene
      result.merge(version: whiteboard.version)
    end

    def find_or_create_whiteboard(chat_session)
      chat_session.whiteboard || chat_session.create_whiteboard!(scene_json: { "elements" => [] })
    end

    def shape_element(type:, x:, y:, width:, height:, color: nil, **)
      base_element(type: type, x: x, y: y, width: width, height: height).merge(
        "backgroundColor" => color.presence || DEFAULT_COLOR,
        "strokeColor" => DEFAULT_STROKE,
        "boundElements" => []
      )
    end

    def text_element(content:, x:, y:, font_size: nil)
      font_size = integer_or_default(font_size, 20)
      text = content.to_s

      base_element(type: "text", x: x, y: y, width: [ text.length * font_size * 0.6, font_size ].max.round(2), height: (font_size * 1.25).round(2)).merge(
        "text" => text,
        "fontSize" => font_size,
        "fontFamily" => 1,
        "textAlign" => "left",
        "verticalAlign" => "top",
        "baseline" => font_size
      )
    end

    # Labels in Excalidraw are not a field on the container shape —
    # they're a separate `text` element bound via `containerId` (and a
    # matching entry in the container's `boundElements` array).
    # Caller pushes both elements onto the scene and sets the
    # container's `boundElements`.
    def bound_label_element(container:, text:, font_size: 20)
      label = text.to_s
      width = [ label.length * font_size * 0.6, font_size * 2 ].max.round(2)
      height = (font_size * 1.25).round(2)
      x = container.fetch("x").to_f + (container.fetch("width").to_f - width) / 2.0
      y = container.fetch("y").to_f + (container.fetch("height").to_f - height) / 2.0

      base_element(type: "text", x: x, y: y, width: width, height: height).merge(
        "text" => label,
        "originalText" => label,
        "fontSize" => font_size,
        "fontFamily" => 1,
        "textAlign" => "center",
        "verticalAlign" => "middle",
        "baseline" => font_size,
        "lineHeight" => 1.25,
        "containerId" => container.fetch("id")
      )
    end

    def arrow_element(from_element, to_element)
      arrow_id = ExcalidrawId.generate
      start = center_of(from_element)
      finish = center_of(to_element)

      base_element(id: arrow_id, type: "arrow", x: start.fetch("x"), y: start.fetch("y"), width: finish.fetch("x") - start.fetch("x"), height: finish.fetch("y") - start.fetch("y")).merge(
        "points" => [ [ 0, 0 ], [ finish.fetch("x") - start.fetch("x"), finish.fetch("y") - start.fetch("y") ] ],
        "startBinding" => { "elementId" => from_element.fetch("id"), "focus" => 0, "gap" => 1 },
        "endBinding" => { "elementId" => to_element.fetch("id"), "focus" => 0, "gap" => 1 }
      )
    end

    def bind_arrow_to_shapes!(elements, arrow)
      %w[startBinding endBinding].each do |binding_key|
        shape = find_element(elements, arrow.fetch(binding_key).fetch("elementId"))
        shape["boundElements"] = Array(shape["boundElements"])
        next if shape["boundElements"].any? { |bound| bound["id"] == arrow.fetch("id") }

        shape["boundElements"] << { "id" => arrow.fetch("id"), "type" => "arrow" }
      end
    end

    def remove_element!(elements, id)
      removed = elements.find { |element| element["id"] == id }
      raise ArgumentError, "unknown element id: #{id}" unless removed

      elements.delete(removed)
      elements.each do |element|
        element["boundElements"] = Array(element["boundElements"]).reject { |bound| bound["id"] == id } if element["boundElements"]
      end

      return unless removed["type"] != "arrow"

      elements.delete_if do |element|
        element["type"] == "arrow" &&
          [ element.dig("startBinding", "elementId"), element.dig("endBinding", "elementId") ].include?(id)
      end
    end

    def recalibrate_bound_arrows!(elements)
      elements.select { |element| element["type"] == "arrow" }.each do |arrow|
        recalibrate_arrow!(arrow, elements)
      end
    end

    def validate_elements!(elements)
      raise ArgumentError, "elements must be an array" unless elements.is_a?(Array)
      ensure_within_element_limit!(elements)

      elements.each do |element|
        raise ArgumentError, "each element must be an object" unless element.is_a?(Hash)

        type = (element["type"] || element[:type]).to_s
        raise ArgumentError, "element type is required" if type.empty?
        raise ArgumentError, "unsupported element type: #{type}" unless ELEMENT_TYPES.include?(type)
      end
    end

    def ensure_can_append_element!(elements)
      raise ElementLimitExceeded, Whiteboard.element_limit_message if elements.size >= Whiteboard::MAX_ELEMENTS
    end

    def ensure_within_element_limit!(elements)
      raise ElementLimitExceeded, Whiteboard.element_limit_message if elements.size > Whiteboard::MAX_ELEMENTS
    end

    def find_element(elements, id)
      element = elements.find { |candidate| candidate["id"] == id }
      raise ArgumentError, "unknown element id: #{id}" unless element

      element
    end

    def number(value, name)
      Float(value)
    rescue ArgumentError, TypeError
      raise ArgumentError, "#{name} must be a number"
    end

    def positive_number(value, name)
      numeric = number(value, name)
      raise ArgumentError, "#{name} must be greater than 0" unless numeric.positive?

      numeric
    end

    def deep_dup_elements(elements)
      JSON.parse(JSON.generate(elements))
    end

    def base_element(type:, x:, y:, width:, height:, id: ExcalidrawId.generate)
      now = (Time.current.to_f * 1000).to_i

      # Visual-style defaults (opacity / strokeWidth / strokeStyle /
      # roughness / fillStyle) must be present on the wire — Excalidraw's
      # `updateScene` (the broadcast-apply path) takes elements as-is
      # without normalizing, and missing values render invisible.
      # `initialData` does normalize, which is why reloads worked but
      # live agent draws came in transparent.
      {
        "id" => id,
        "type" => type,
        "x" => x,
        "y" => y,
        "width" => width,
        "height" => height,
        "angle" => 0,
        "strokeWidth" => 2,
        "strokeStyle" => "solid",
        "fillStyle" => "solid",
        "roughness" => 1,
        "opacity" => 100,
        "seed" => SecureRandom.random_number(1 << 31),
        "version" => 1,
        "versionNonce" => SecureRandom.random_number(1 << 31),
        "isDeleted" => false,
        "groupIds" => [],
        "frameId" => nil,
        "roundness" => nil,
        "updated" => now,
        "link" => nil,
        "locked" => false
      }
    end

    def center_of(element)
      {
        "x" => element.fetch("x").to_f + (element.fetch("width").to_f / 2),
        "y" => element.fetch("y").to_f + (element.fetch("height").to_f / 2)
      }
    end

    def recalibrate_arrow!(arrow, elements)
      start_id = arrow.dig("startBinding", "elementId")
      end_id = arrow.dig("endBinding", "elementId")
      return if start_id.blank? || end_id.blank?

      start_element = elements.find { |element| element["id"] == start_id }
      end_element = elements.find { |element| element["id"] == end_id }
      return unless start_element && end_element

      start = center_of(start_element)
      finish = center_of(end_element)
      arrow["x"] = start.fetch("x")
      arrow["y"] = start.fetch("y")
      arrow["width"] = finish.fetch("x") - start.fetch("x")
      arrow["height"] = finish.fetch("y") - start.fetch("y")
      arrow["points"] = [ [ 0, 0 ], [ arrow["width"], arrow["height"] ] ]
      arrow["version"] = arrow.fetch("version", 0).to_i + 1
      arrow["updated"] = (Time.current.to_f * 1000).to_i
    end

    def integer_or_default(value, default)
      return default if value.blank?

      Integer(value)
    rescue ArgumentError, TypeError
      raise ArgumentError, "font_size must be an integer"
    end
  end
end
