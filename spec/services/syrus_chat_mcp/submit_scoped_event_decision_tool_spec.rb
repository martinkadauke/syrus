require "rails_helper"

RSpec.describe Mcp::Tools::SubmitScopedEventDecisionTool do
  let(:user) { Factories.user }
  let(:chat_session) { ChatSession.create!(user: user, chat_provider: "claude") }
  let(:event) do
    ChatScopedEvent.create!(
      chat_session: chat_session,
      source_kind: "job_failed",
      payload: { "severity" => "critical", "summary" => "Job failed" }
    )
  end

  def response_text(response)
    response.content.first[:text]
  end

  it "stores a structured decision for the running evaluator session" do
    event.mark_evaluator_running!(session_id: "chat-eval-1")

    response = described_class.call(
      decision: "act",
      reason: "operator should inspect",
      urgency: 1.2,
      confidence: -0.2,
      handoff_prompt: "Inspect the job failure.",
      server_context: {
        chat_session: chat_session,
        evaluator: true,
        scoped_event_id: event.id,
        evaluator_session_id: "chat-eval-1"
      }
    )

    expect(response).not_to be_error
    expect(JSON.parse(response_text(response))).to include("saved" => true, "decision" => "act")
    expect(event.reload.evaluator_result).to include(
      "decision" => "act",
      "reason" => "operator should inspect",
      "urgency" => 1.0,
      "confidence" => 0.0,
      "submitted_via" => "mcp_tool"
    )
  end

  it "rejects mismatched evaluator sessions" do
    event.mark_evaluator_running!(session_id: "chat-eval-1")

    response = described_class.call(
      decision: "act",
      reason: "operator should inspect",
      urgency: 1,
      confidence: 1,
      server_context: {
        chat_session: chat_session,
        evaluator: true,
        scoped_event_id: event.id,
        evaluator_session_id: "chat-eval-2"
      }
    )

    expect(response).to be_error
    expect(response_text(response)).to include("evaluator session mismatch")
    expect(event.reload.evaluator_result).to be_nil
  end
end
