require "mcp"

module Mcp
  class Sidecar
    CHAT_ESSENTIAL_SERVER = "syrus-chat-sidecar"
    CHAT_DEFERRED_SERVER = "syrus-chat-deferred-sidecar"
    WORKFLOW_SERVER = "syrus-mcp-sidecar"

    CHAT_ESSENTIAL_TOOLS = McpToolRegistry.tools(surface: :chat, tier: :essential).freeze
    CHAT_DEFERRED_TOOLS = McpToolRegistry.tools(surface: :chat, tier: :deferred).freeze
    CHAT_ADMIN_TOOLS = McpToolRegistry.entries.select { |entry| entry.surface == :chat && entry.admin_only }.map(&:tool).freeze
    CHAT_WALKTHROUGH_TOOLS = McpToolRegistry.entries.select { |entry| entry.surface == :chat && entry.feature_flag == :video_walkthroughs }.map(&:tool).freeze
    CHAT_CODING_TOOLS = McpToolRegistry.entries.select { |entry| entry.surface == :chat && entry.required_roles.include?(AgentRole::CHAT_CODING) }.map(&:tool).freeze
    CHAT_LOCAL_MODE_TOOLS = McpToolRegistry.entries.select { |entry| entry.surface == :chat && entry.required_roles.include?(AgentRole::CHAT_LOCAL) }.map(&:tool).freeze

    def self.chat(session_id:, current_message_id: nil, tier: :essential, server_name: nil)
      tier = tier.to_sym
      default_name = tier == :deferred ? CHAT_DEFERRED_SERVER : CHAT_ESSENTIAL_SERVER
      evaluator = tier == :evaluator
      new(
        server_name: server_name.presence || default_name,
        tools: -> { chat_tools_for(ChatSession.find(session_id), tier: tier) },
        server_context: -> {
          chat_context(
            ChatSession.find(session_id),
            current_message_id: current_message_id,
            evaluator: evaluator,
            scoped_event_id: ENV["SYRUS_CHAT_SCOPED_EVENT_ID"],
            evaluator_session_id: ENV["SYRUS_CHAT_EVALUATOR_SESSION_ID"]
          )
        }
      )
    end

    def self.workflow(run_id:)
      new(
        server_name: WORKFLOW_SERVER,
        tools: lambda {
          Tools.with_database_connection do
            context = McpToolContext.from_run(Run.includes(:step, job: :repository).find(run_id))
            McpToolPolicy.for(context) + plugin_workflow_tools_for(context)
          end
        },
        server_context: -> { { run_id: run_id } }
      )
    end

    def self.chat_tool_names(chat_session = nil, tier: :essential)
      chat_tools(chat_session, tier: tier).map { |tool| tool.name.demodulize.sub(/Tool\z/, "").underscore }
    end

    def self.tool_names(chat_session = nil, tier: :essential)
      chat_tool_names(chat_session, tier: tier)
    end

    def self.chat_tools(chat_session = nil, tier: :essential)
      return McpToolRegistry.tools(surface: :chat, tier: tier) unless chat_session

      chat_tools_for(chat_session, tier: tier)
    end

    def self.chat_tools_for(chat_session, tier:)
      evaluator = tier.to_s == "evaluator"
      context = McpToolContext.from_chat_session(chat_session, evaluator: evaluator)
      if evaluator
        McpToolPolicy.for(context).map { |tool| authorize_tool(tool) }
      else
        registry_tier = tier.to_s == "all" ? :essential : tier
        allowed = McpToolRegistry.tools_for_context(context, surface: :chat, tier: registry_tier)
        if context.chat_session&.system_kind_supervisor?
          allowed -= McpToolPolicy::SUPERVISOR_EXCLUDED_TOOLS
        end
        tools = allowed.map { |tool| authorize_tool(tool) }
        tools << authorize_tool(Tools::ExplainStuckJobTool) if tier.to_s == "all" && !tools.include?(Tools::ExplainStuckJobTool)
        tools + plugin_tools_for(chat_session, tier: registry_tier)
      end
    end

    def self.plugin_tools_for(chat_session, tier:)
      tool_sets = PerformanceLogging.phase("chat_mcp_sidecar.plugin_tool_sets", chat_id: chat_session.id, tier: tier) do
        Syrus::PluginRegistry.providers_for(:chat_mcp_tool_set)
      end

      tool_sets
        .select do |tool_set|
          PerformanceLogging.plugin_call(extension_point: :chat_mcp_tool_set, provider: tool_set, operation: :available_for) do
            tool_set.available_for?(chat_session, tier: tier)
          end
        end
        .flat_map { |tool_set| mcp_tools_for(tool_set, tier: tier) }
    end

    def self.mcp_tools_for(tool_set_class, tier:)
      definitions = PerformanceLogging.plugin_call(extension_point: :chat_mcp_tool_set, provider: tool_set_class, operation: :tool_definitions) do
        tool_set_class.tool_definitions(tier: tier)
      end

      definitions.map do |defn|
        MCP::Tool.define(
          name: defn[:name],
          description: defn[:description],
          input_schema: defn[:input_schema]
        ) do |server_context:, **params|
          PerformanceLogging.plugin_call(extension_point: :chat_mcp_tool_set, provider: tool_set_class, operation: "handle.#{defn[:name]}") do
            tool_set_class.new.handle(defn[:name], params, server_context)
          end
        end
      end
    end

    def self.plugin_workflow_tools_for(context)
      tool_sets = PerformanceLogging.phase("workflow_mcp_sidecar.plugin_tool_sets", repository_id: context.repository&.id) do
        Syrus::PluginRegistry.providers_for(:mcp_tool_set)
      end

      tool_sets
        .select do |tool_set|
          PerformanceLogging.plugin_call(extension_point: :mcp_tool_set, provider: tool_set, operation: :available_for) do
            if tool_set.respond_to?(:available_for_context?)
              tool_set.available_for_context?(context)
            else
              tool_set.available_for?(context.repository)
            end
          end
        end
        .flat_map { |tool_set| workflow_mcp_tools_for(tool_set, context: context) }
    end

    def self.workflow_mcp_tools_for(tool_set_class, context:)
      definitions = PerformanceLogging.plugin_call(extension_point: :mcp_tool_set, provider: tool_set_class, operation: :tool_definitions) do
        if tool_set_class.method(:tool_definitions).parameters.any? { |type, name| [ :key, :keyreq ].include?(type) && name == :context }
          tool_set_class.tool_definitions(context: context)
        else
          tool_set_class.tool_definitions
        end
      end
      policy_managed_names = defined?(SyrusMcp::CoreToolSet::POLICY_MANAGED_NAMES) ? SyrusMcp::CoreToolSet::POLICY_MANAGED_NAMES : []

      definitions.reject { |defn| policy_managed_names.include?(defn[:name]) }.map do |defn|
        MCP::Tool.define(
          name: defn[:name],
          description: defn[:description],
          input_schema: defn[:input_schema]
        ) do |server_context:, **params|
          PerformanceLogging.plugin_call(extension_point: :mcp_tool_set, provider: tool_set_class, operation: "handle.#{defn[:name]}") do
            tool_set_class.new.handle(defn[:name], params, server_context)
          end
        end
      end
    end

    def self.authorize_tool(tool)
      tool.extend(Tools::AuthorizationSupport) unless tool.singleton_class < Tools::AuthorizationSupport
      tool.singleton_class.prepend(Tools::AuthorizationSupport::ToolDispatch) unless tool.singleton_class < Tools::AuthorizationSupport::ToolDispatch
      tool
    end

    def self.chat_context(chat_session, current_message_id:, evaluator: false, scoped_event_id: nil, evaluator_session_id: nil)
      current_message = if current_message_id.present?
        chat_session.messages.find_by(id: current_message_id)
      else
        Tools::CurrentMessage.new(chat_session)
      end

      {
        chat_session: chat_session,
        current_message: current_message,
        evaluator: evaluator ? true : nil,
        scoped_event_id: scoped_event_id.presence,
        evaluator_session_id: evaluator_session_id.presence
      }.compact
    end

    def initialize(server_name:, tools:, server_context:)
      @server_name = server_name
      @tools = tools
      @server_context = server_context
    end

    def build_server
      MCP::Server.new(
        name: @server_name,
        tools: @tools.call,
        server_context: @server_context.call
      )
    end

    def run
      at_exit { Tools::AgentPreviewRegistry.kill_all }

      server = build_server
      transport = MCP::Server::Transports::StdioTransport.new(server)

      Signal.trap("TERM") { transport.close; exit 0 }

      transport.open
    end
  end
end
