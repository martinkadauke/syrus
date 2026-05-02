require "mcp"

module SyrusMcp
  # Per-run MCP server, spawned over stdio by `claude` itself. Process
  # is short-lived: starts when claude opens it, exits when claude
  # closes its stdin (or sends SIGTERM). All it needs to know is the
  # run_id; everything else comes from the DB.
  class Sidecar
    def initialize(run_id:)
      @run = Run.find(run_id)
    end

    def run
      server = MCP::Server.new(
        name: "syrus",
        tools: [SubmitSummaryTool],
        server_context: { run: @run }
      )
      transport = MCP::Server::Transports::StdioTransport.new(server)

      # Claude sends SIGTERM when it's done. Close cleanly so the
      # while-loop in StdioTransport#open exits without an exception.
      Signal.trap("TERM") { transport.close; exit 0 }

      transport.open
    end
  end
end
