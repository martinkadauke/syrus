require "rails_helper"

RSpec.describe ChatScopedEventRetryFailedJob do
  include ActiveJob::TestHelper

  let(:user) { Factories.user }
  let(:chat_session) { ChatSession.create!(user: user, chat_provider: "claude") }

  def scoped_event(delivery_state: "pending", created_at: Time.current)
    ChatScopedEvent.create!(
      chat_session: chat_session,
      source_kind: "pull_request_merged",
      payload: { "severity" => "info", "summary" => "PR merged" },
      delivery_state: delivery_state,
      created_at: created_at
    )
  end

  it "resets recent failed pending evaluator events and enqueues evaluation" do
    event = scoped_event
    event.record_evaluator_failure!("JSON::ParserError: evaluator did not return JSON")

    expect {
      described_class.perform_now
    }.to have_enqueued_job(ChatScopedEventEvaluatorJob).with(event.id, chat_session.id)

    event.reload
    expect(event.evaluator_state).to eq("pending")
    expect(event.evaluator_error).to be_nil
    expect(event.evaluator_result).to be_nil
  end

  it "does not retry already delivered or old failed events" do
    delivered = scoped_event(delivery_state: "delivered")
    old = scoped_event(created_at: 2.days.ago)
    delivered.record_evaluator_failure!("failed")
    old.record_evaluator_failure!("failed")

    expect {
      described_class.perform_now
    }.not_to have_enqueued_job(ChatScopedEventEvaluatorJob)

    expect(delivered.reload.evaluator_state).to eq("failed")
    expect(old.reload.evaluator_state).to eq("failed")
  end
end
