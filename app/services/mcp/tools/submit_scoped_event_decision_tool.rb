require "mcp"

module Mcp::Tools
  class SubmitScopedEventDecisionTool < MCP::Tool
    tool_name "submit_scoped_event_decision"

    description <<~DESC
      Stores the structured decision for the scoped chat event being evaluated.
      This tool is only available to disposable chat event evaluator sessions.
    DESC

    input_schema(
      properties: {
        decision: {
          type: "string",
          enum: ChatEventEvaluator::DECISIONS,
          description: "Whether the event needs no chat activity, a visible response, or a live-agent handoff."
        },
        reason: {
          type: "string",
          description: "A concise reason for the decision."
        },
        urgency: {
          type: "number",
          description: "0.0 to 1.0 urgency."
        },
        confidence: {
          type: "number",
          description: "0.0 to 1.0 confidence."
        },
        handoff_prompt: {
          type: "string",
          description: "Optional concise prompt for the live chat agent when decision is respond or act."
        }
      },
      required: %w[decision reason urgency confidence]
    )

    class << self
      def call(decision:, reason:, urgency:, confidence:, server_context:, handoff_prompt: nil)
        event = event_from_context(server_context)
        return event unless event.is_a?(ChatScopedEvent)
        return Mcp::Tools.invalid("scoped event is already delivered") if event.delivered?
        return Mcp::Tools.invalid("scoped event evaluator is not running") unless event.evaluator_state == "running"

        expected_session_id = server_context[:evaluator_session_id].to_s.presence
        if expected_session_id.present? && event.evaluator_session_id != expected_session_id
          return Mcp::Tools.invalid("evaluator session mismatch")
        end

        normalized_decision = Mcp::Tools.utf8(decision).strip
        return Mcp::Tools.invalid("decision must be one of #{ChatEventEvaluator::DECISIONS.join(', ')}") unless ChatEventEvaluator::DECISIONS.include?(normalized_decision)

        normalized_reason = Mcp::Tools.utf8(reason).strip
        return Mcp::Tools.invalid("reason is required") if normalized_reason.blank?

        payload = {
          "decision" => normalized_decision,
          "reason" => normalized_reason,
          "urgency" => clamp_float(urgency),
          "confidence" => clamp_float(confidence),
          "handoff_prompt" => Mcp::Tools.utf8(handoff_prompt).strip.presence,
          "submitted_via" => "mcp_tool"
        }.compact

        event.update!(evaluator_result: payload)
        Mcp::Tools.success(saved: true, decision: normalized_decision)
      rescue StandardError => e
        Rails.logger.error("[Mcp::Tools::SubmitScopedEventDecisionTool] #{e.class}: #{e.message}")
        Mcp::Tools.invalid("#{e.class}: #{e.message}")
      end

      private

      def event_from_context(server_context)
        return Mcp::Tools.invalid("not an evaluator session") unless server_context[:evaluator] == true

        chat_session = server_context[:chat_session]
        event_id = Integer(server_context[:scoped_event_id], exception: false)
        return Mcp::Tools.invalid("scoped_event_id is missing") unless event_id

        event = ChatScopedEvent.find_by(id: event_id)
        return Mcp::Tools.invalid("scoped event not found") unless event
        return Mcp::Tools.invalid("scoped event does not belong to this chat") if chat_session && event.chat_session_id != chat_session.id

        event
      end

      def clamp_float(value)
        numeric = Float(value, exception: false) || 0.0
        [ [ numeric, 0.0 ].max, 1.0 ].min
      end
    end
  end
end
