require "rails_helper"

RSpec.describe ChatCodingWorkspaceReclaimJob do
  let(:user) { Factories.user }
  let(:chat_session) { ChatSession.create!(user: user, coding_checkout_branch: "syrus-chat-1") }

  it "runs on the chat queue (where the workspace disk lives)" do
    expect(described_class.new.queue_name).to eq("chat")
  end

  it "reclaims the coding checkout for a session that has one" do
    expect(ChatWorkspace).to receive(:reclaim_coding_checkout!).with(chat_session)

    described_class.perform_now(chat_session.id)
  end

  it "no-ops for a session with no coding checkout" do
    planning = ChatSession.create!(user: user)
    expect(ChatWorkspace).not_to receive(:reclaim_coding_checkout!)

    described_class.perform_now(planning.id)
  end

  it "no-ops for a missing session" do
    expect(ChatWorkspace).not_to receive(:reclaim_coding_checkout!)

    expect { described_class.perform_now(-1) }.not_to raise_error
  end

  it "swallows reclaim errors so a transient failure doesn't crash the job" do
    allow(ChatWorkspace).to receive(:reclaim_coding_checkout!).and_raise(StandardError, "boom")

    expect { described_class.perform_now(chat_session.id) }.not_to raise_error
  end
end
