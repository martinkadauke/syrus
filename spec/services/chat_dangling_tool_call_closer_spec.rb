require "rails_helper"

RSpec.describe ChatDanglingToolCallCloser do
  it "closes a dangling tool call after the latest user message" do
    user = Factories.user
    chat = ChatSession.create!(user: user)
    chat.messages.create!(role: "user", content: { "text" => "Look around" })
    chat.messages.create!(
      role: "tool_use",
      tool_name: "syrus-chat-sidecar.admin_overview",
      tool_use_id: "item_1",
      content: {
        "type" => "tool_use",
        "id" => "item_1",
        "name" => "syrus-chat-sidecar.admin_overview",
        "input" => {}
      }
    )

    expect {
      described_class.close!(chat_session: chat, message: "Cancelled by operator before this tool returned.")
    }.to change { chat.messages.where(role: "tool_result").count }.by(1)

    result = chat.messages.find_by!(role: "tool_result", tool_use_id: "item_1")
    expect(result.tool_name).to eq("syrus-chat-sidecar.admin_overview")
    expect(result.content).to include(
      "type" => "tool_result",
      "tool_use_id" => "item_1",
      "is_error" => true
    )
    expect(result.content.dig("content", 0, "text")).to eq("Cancelled by operator before this tool returned.")
  end

  it "does not treat a same-id tool result from an older turn as answering the latest turn" do
    user = Factories.user
    chat = ChatSession.create!(user: user)
    chat.messages.create!(role: "user", content: { "text" => "Earlier turn" })
    chat.messages.create!(
      role: "tool_use",
      tool_name: "syrus-chat-sidecar.admin_overview",
      tool_use_id: "item_1",
      content: { "type" => "tool_use", "id" => "item_1", "name" => "syrus-chat-sidecar.admin_overview", "input" => {} }
    )
    chat.messages.create!(
      role: "tool_result",
      tool_name: "syrus-chat-sidecar.admin_overview",
      tool_use_id: "item_1",
      content: { "type" => "tool_result", "tool_use_id" => "item_1", "content" => "ok", "is_error" => false }
    )
    chat.messages.create!(role: "user", content: { "text" => "Latest turn" })
    chat.messages.create!(
      role: "tool_use",
      tool_name: "syrus-chat-sidecar.admin_overview",
      tool_use_id: "item_1",
      content: { "type" => "tool_use", "id" => "item_1", "name" => "syrus-chat-sidecar.admin_overview", "input" => {} }
    )

    expect {
      described_class.close!(chat_session: chat, message: "Cancelled by operator before this tool returned.")
    }.to change { chat.messages.where(role: "tool_result").count }.by(1)
  end
end
