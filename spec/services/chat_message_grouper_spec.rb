require "rails_helper"

RSpec.describe ChatMessageGrouper do
  let(:user) { Factories.user(claude_oauth_token: "oat") }
  let(:repo) { Factories.repository(user: user, owner: "acme", name: "widgets") }
  let(:chat) { ChatSession.create!(repository: repo, user: user, last_message_at: Time.current) }

  def msg(role, text, tool_name: nil)
    chat.messages.create!(role: role, tool_name: tool_name, content: { "text" => text })
  end

  it "passes through plain user/assistant/system messages" do
    u = msg("user", "hi")
    a = msg("assistant", "hello")
    s = msg("system", "ok")

    items = described_class.group([ u, a, s ])

    expect(items).to eq([
      { type: :message, message: u },
      { type: :message, message: a },
      { type: :message, message: s }
    ])
  end

  it "groups consecutive abbreviated tool_use messages of the same tool name" do
    a = msg("tool_use", "● Read(a.py)")
    b = msg("tool_use", "● Read(b.py)")
    c = msg("tool_use", "● Read(c.py)")

    items = described_class.group([ a, b, c ])

    expect(items.size).to eq(1)
    group = items.first
    expect(group[:type]).to eq(:tool_group)
    expect(group[:tool]).to eq("Read")
    expect(group[:calls].map { |c| c[:detail] }).to eq([ "a.py", "b.py", "c.py" ])
  end

  it "starts a new group when the tool name changes" do
    r = msg("tool_use", "● Read(a.py)")
    b = msg("tool_use", "● Bash(ls)")

    items = described_class.group([ r, b ])

    expect(items.map { |i| i[:tool] }).to eq([ "Read", "Bash" ])
  end

  it "attaches an abbreviated tool_result to the last tool_use in the current group" do
    a = msg("tool_use", "● Read(a.py)")
    r = msg("tool_result", "  ⎿ file contents...")

    items = described_class.group([ a, r ])

    group = items.first
    expect(group[:calls].first[:result]).to eq(r)
  end

  it "leaves structured (canvas) tool_use messages as standalone passthroughs" do
    chat.messages.create!(role: "tool_use", tool_name: "draw_box", content: { "x" => 10, "y" => 20 })
    structured = chat.messages.last

    items = described_class.group([ structured ])

    expect(items).to eq([ { type: :message, message: structured } ])
  end

  it "breaks the current group when a non-tool message arrives between calls" do
    a = msg("tool_use", "● Read(a.py)")
    u = msg("assistant", "Done.")
    b = msg("tool_use", "● Read(b.py)")

    items = described_class.group([ a, u, b ])

    expect(items.map { |i| i[:type] }).to eq([ :tool_group, :message, :tool_group ])
  end
end
