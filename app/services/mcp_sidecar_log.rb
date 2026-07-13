require "pathname"

class McpSidecarLog
  MAX_CAPTURE_BYTES = 16.kilobytes

  def self.path_for(run_id)
    root.join("run-#{run_id}.stderr.log")
  end

  def self.chat_path_for(chat_session_id, message_id:, server_name:)
    root.join(
      "chat-#{chat_session_id}-message-#{message_id}-#{safe_filename(server_name)}.stderr.log"
    )
  end

  def self.tail(run_id, max_bytes: MAX_CAPTURE_BYTES)
    path = path_for(run_id)
    tail_path(path, max_bytes: max_bytes)
  end

  def self.tail_chat(chat_session_id, message_id:, server_name:, max_bytes: MAX_CAPTURE_BYTES)
    path = chat_path_for(chat_session_id, message_id: message_id, server_name: server_name)
    tail_path(path, max_bytes: max_bytes)
  end

  def self.root
    data_root = ENV["SYRUS_DATA_ROOT"].presence || File.expand_path("~/.syrus")
    Pathname.new(data_root).join("mcp-sidecar-logs")
  end

  def self.safe_filename(value)
    value.to_s.gsub(/[^A-Za-z0-9_.-]/, "_").presence || "unknown"
  end

  def self.tail_path(path, max_bytes:)
    return "" unless path.file?

    size = path.size
    offset = [ size - max_bytes, 0 ].max
    File.binread(path, max_bytes, offset).to_s.force_encoding(Encoding::UTF_8).scrub
  rescue StandardError => e
    "failed to read MCP sidecar stderr log #{path}: #{e.class}: #{e.message}"
  end

  private_class_method :tail_path
end
