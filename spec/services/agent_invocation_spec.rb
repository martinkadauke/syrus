require "rails_helper"

RSpec.describe AgentInvocation do
  def result_fixture(**overrides)
    defaults = { turns: 2, exit_status: 0, timed_out: false, is_error: false, outcome: "success" }
    AgentInvocation::Result.new(**defaults.merge(overrides))
  end

  describe "#run" do
    it "delegates to the injected runner with all the kwargs" do
      received = {}
      runner = ->(**kwargs) {
        received.merge!(kwargs)
        result_fixture(turns: 2)
      }

      result = described_class.new("/tmp/wkt", prompt: "do the thing", oauth_token: "oat-x",
                                   runner: runner, timeout: 60, max_turns: 7).run

      expect(received[:workspace_path]).to eq("/tmp/wkt")
      expect(received[:prompt]).to eq("do the thing")
      expect(received[:oauth_token]).to eq("oat-x")
      expect(received[:timeout]).to eq(60)
      expect(received[:max_turns]).to eq(7)
      expect(result.turns).to eq(2)
      expect(result).to be_success
    end
  end

  describe AgentInvocation::Result do
    it "is success when not timed out, exit_status 0, and not is_error" do
      r = described_class.new(turns: 1, exit_status: 0, timed_out: false, is_error: false, outcome: "success")
      expect(r).to be_success
    end

    it "is not success when timed_out" do
      r = described_class.new(turns: 30, exit_status: nil, timed_out: true, is_error: false, outcome: nil)
      expect(r).not_to be_success
    end

    it "is not success when exit_status non-zero" do
      r = described_class.new(turns: 1, exit_status: 1, timed_out: false, is_error: false, outcome: nil)
      expect(r).not_to be_success
    end

    it "is not success when is_error is true (e.g. error_max_turns)" do
      r = described_class.new(turns: 50, exit_status: 0, timed_out: false, is_error: true, outcome: "error_max_turns")
      expect(r).not_to be_success
    end
  end

  describe "stream-json event parsing" do
    let(:lines) { [] }
    let(:invocation) { described_class.new("/tmp", prompt: "x", oauth_token: "x", log_sink: ->(l) { lines << l }) }

    it "extracts assistant text into the log_sink" do
      event = { type: "assistant", message: { content: [ { type: "text", text: "Looking at the issue..." } ] } }.to_json
      result = invocation.send(:process_event, event, ->(l) { lines << l })
      expect(lines.last).to eq("Looking at the issue...")
      expect(result).to be_nil
    end

    it "captures num_turns + is_error + outcome from the result event" do
      event = { type: "result", num_turns: 5, duration_ms: 12345, is_error: false, subtype: "success" }.to_json
      update = invocation.send(:process_event, event, ->(l) { lines << l })
      expect(update).to eq(turns: 5, is_error: false, outcome: "success")
      expect(lines.last).to match(/subtype=success/).and match(/turns=5/)
    end

    it "captures error subtype on max-turns" do
      event = { type: "result", num_turns: 50, is_error: true, subtype: "error_max_turns" }.to_json
      update = invocation.send(:process_event, event, ->(l) { lines << l })
      expect(update).to include(is_error: true, outcome: "error_max_turns")
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
