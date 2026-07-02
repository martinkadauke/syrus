require "pathname"

class McpSidecarLog
  MAX_CAPTURE_BYTES = 16.kilobytes

  def self.path_for(run_id)
    root.join("run-#{run_id}.stderr.log")
  end

  def self.tail(run_id, max_bytes: MAX_CAPTURE_BYTES)
    path = path_for(run_id)
    return "" unless path.file?

    size = path.size
    offset = [ size - max_bytes, 0 ].max
    File.binread(path, max_bytes, offset).to_s.force_encoding(Encoding::UTF_8).scrub
  rescue StandardError => e
    "failed to read MCP sidecar stderr log #{path}: #{e.class}: #{e.message}"
  end

  def self.root
    data_root = ENV["SYRUS_DATA_ROOT"].presence || File.expand_path("~/.syrus")
    Pathname.new(data_root).join("mcp-sidecar-logs")
  end
end
