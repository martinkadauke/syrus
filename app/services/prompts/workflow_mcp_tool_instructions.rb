module Prompts
  module WorkflowMcpToolInstructions
    SERVER_NAME = "syrus-mcp-sidecar"

    def self.claude_tool_name(tool_name)
      "mcp__#{SERVER_NAME}__#{tool_name}"
    end

    def self.codex_tool_name(tool_name)
      "#{SERVER_NAME}.#{tool_name}"
    end

    def self.tool_name_for(provider, tool_name)
      case provider.to_s
      when "claude", "claude_agent"
        claude_tool_name(tool_name)
      when "codex", "codex_agent"
        codex_tool_name(tool_name)
      end
    end
  end
end
