module Admin
  module Transcripts
    class Payload
      DEFAULT_PER_PAGE = 100
      MAX_PER_PAGE = 500

      def initialize(params:)
        @params = params
      end

      def show(run_id)
        run = Run.find(run_id)
        session = run.claude_session
        return missing_session_payload(run) unless session

        transcript = ClaudeTranscript.new(session.transcript_jsonl)
        all_events = transcript.events.to_a
        page = [ params.fetch(:page, 1).to_i, 1 ].max
        per = [ [ params.fetch(:per, DEFAULT_PER_PAGE).to_i, 1 ].max, MAX_PER_PAGE ].min
        slice = all_events.slice((page - 1) * per, per) || []

        {
          run_id: run.id,
          job_id: run.job_id,
          step_kind: run.step&.kind,
          workflow_trigger_kind: run.step&.workflow&.trigger_kind,
          session_id: session.session_id,
          summary: serialize_summary(transcript.summary),
          pagination: {
            page: page,
            per: per,
            total_events: all_events.size,
            total_pages: [ (all_events.size.to_f / per).ceil, 1 ].max
          },
          events: slice.map { |event| serialize_event(event) }
        }
      end

      private

      attr_reader :params

      def missing_session_payload(run)
        {
          error: {
            code: "not_found",
            message: "No agent session captured for Run ##{run.id}."
          },
          status: :not_found
        }
      end

      def serialize_summary(summary)
        {
          session_id: summary.session_id,
          model: summary.model,
          cwd: summary.cwd,
          total_turns: summary.total_turns,
          total_tool_calls: summary.total_tool_calls,
          total_cost_usd: summary.total_cost_usd,
          exit_reason: summary.exit_reason,
          tool_call_counts: summary.tool_call_counts,
          mcp_tool_called: summary.mcp_tool_called?,
          available_tools_at_init: summary.available_tools_at_init
        }
      end

      def serialize_event(event)
        { kind: event.kind.to_s, timestamp: event.timestamp, data: event.data }
      end
    end
  end
end
