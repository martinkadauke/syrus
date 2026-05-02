require "rails_helper"

RSpec.describe AgentInvocation do
  describe "#run" do
    it "delegates to the injected runner with all the kwargs" do
      received = {}
      runner = ->(**kwargs) {
        received.merge!(kwargs)
        AgentInvocation::Result.new(turns: 2, exit_status: 0, timed_out: false)
      }

      result = described_class.new("/tmp/wkt", prompt: "do the thing", api_key: "sk-x",
                                   runner: runner, timeout: 60, max_turns: 7).run

      expect(received[:workspace_path]).to eq("/tmp/wkt")
      expect(received[:prompt]).to eq("do the thing")
      expect(received[:api_key]).to eq("sk-x")
      expect(received[:timeout]).to eq(60)
      expect(received[:max_turns]).to eq(7)
      expect(result.turns).to eq(2)
      expect(result).to be_success
    end
  end

  describe AgentInvocation::Result do
    it "is success when not timed out and exit_status is 0" do
      r = described_class.new(turns: 1, exit_status: 0, timed_out: false)
      expect(r).to be_success
    end

    it "is not success when timed_out" do
      r = described_class.new(turns: 30, exit_status: nil, timed_out: true)
      expect(r).not_to be_success
    end

    it "is not success when exit_status non-zero" do
      r = described_class.new(turns: 1, exit_status: 1, timed_out: false)
      expect(r).not_to be_success
    end
  end

  describe "stream-json event parsing" do
    let(:lines) { [] }
    let(:invocation) { described_class.new("/tmp", prompt: "x", api_key: "x", log_sink: ->(l) { lines << l }) }

    it "extracts assistant text into the log_sink" do
      event = { type: "assistant", message: { content: [ { type: "text", text: "Looking at the issue..." } ] } }.to_json
      result = invocation.send(:process_event, event, ->(l) { lines << l })
      expect(lines.last).to eq("Looking at the issue...")
      expect(result).to be_nil
    end

    it "captures num_turns from the result event" do
      event = { type: "result", num_turns: 5, duration_ms: 12345 }.to_json
      result = invocation.send(:process_event, event, ->(l) { lines << l })
      expect(result).to eq(5)
      expect(lines.last).to match(/turns=5/)
    end

    it "passes non-JSON lines through verbatim" do
      result = invocation.send(:process_event, "not json", ->(l) { lines << l })
      expect(lines.last).to eq("not json")
      expect(result).to be_nil
    end

    it "ignores unknown event types" do
      event = { type: "unknown", foo: "bar" }.to_json
      result = invocation.send(:process_event, event, ->(l) { lines << l })
      expect(lines).to be_empty
      expect(result).to be_nil
    end
  end
end
