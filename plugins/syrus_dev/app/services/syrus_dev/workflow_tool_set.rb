module SyrusDev
  class WorkflowToolSet
    include Syrus::Plugin::McpToolSet

    TOOL_CLASSES = [
      ReadPerformanceDiagnosticsTool,
      ReadSyrusLogsTool
    ].freeze

    def self.available_for?(repository)
      McpToolPolicy.syrus_repository?(repository)
    end

    def self.tool_definitions
      TOOL_CLASSES.map do |klass|
        {
          name: klass.tool_name,
          description: klass.description_value,
          input_schema: klass.input_schema_value.to_h
        }
      end
    end

    def handle(tool_name, params, context)
      klass = TOOL_CLASSES.find { |k| k.tool_name == tool_name }
      raise "SyrusDev::WorkflowToolSet: unknown tool #{tool_name.inspect}" unless klass

      klass.call(**params, server_context: context)
    end
  end
end
