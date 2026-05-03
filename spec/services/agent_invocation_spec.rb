require "rails_helper"

RSpec.describe AgentInvocation do
  def result_fixture(**overrides)
    defaults = { turns: 2, exit_status: 0, timed_out: false, is_error: false, outcome: "success", final_text: nil }
    AgentInvocation::Result.new(**defaults.merge(overrides), session_id: nil)
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
      expect(received[:mcp_config]).to be_nil
      expect(result.turns).to eq(2)
      expect(result).to be_success
    end

    it "passes mcp_config through to the runner when set" do
      received = {}
      runner = ->(**kwargs) {
        received.merge!(kwargs)
        result_fixture
      }

      described_class.new("/tmp/wkt", prompt: "x", oauth_token: "x",
                          runner: runner, mcp_config: "/tmp/mcp.json").run

      expect(received[:mcp_config]).to eq("/tmp/mcp.json")
    end
  end

  describe AgentInvocation::Result do
    it "is success when not timed out, exit_status 0, and not is_error" do
      r = described_class.new(turns: 1, exit_status: 0, timed_out: false, is_error: false, outcome: "success", final_text: nil, session_id: nil)
      expect(r).to be_success
    end

    it "is not success when timed_out" do
      r = described_class.new(turns: 30, exit_status: nil, timed_out: true, is_error: false, outcome: nil, final_text: nil, session_id: nil)
      expect(r).not_to be_success
    end

    it "is not success when exit_status non-zero" do
      r = described_class.new(turns: 1, exit_status: 1, timed_out: false, is_error: false, outcome: nil, final_text: nil, session_id: nil)
      expect(r).not_to be_success
    end

    it "is not success when is_error is true (e.g. error_max_turns)" do
      r = described_class.new(turns: 50, exit_status: 0, timed_out: false, is_error: true, outcome: "error_max_turns", final_text: nil, session_id: nil)
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
      expect(update).to eq(turns: 5, is_error: false, outcome: "success", final_text: nil)
      expect(lines.last).to match(/subtype=success/).and match(/turns=5/)
    end

    it "captures error subtype on max-turns" do
      event = { type: "result", num_turns: 50, is_error: true, subtype: "error_max_turns" }.to_json
      update = invocation.send(:process_event, event, ->(l) { lines << l })
      expect(update).to include(is_error: true, outcome: "error_max_turns", final_text: nil)
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

    it "captures session_id from the system/init event" do
      event = { type: "system", subtype: "init", session_id: "abc-123-xyz", cwd: "/x" }.to_json
      update = invocation.send(:process_event, event, ->(l) { lines << l })
      expect(update).to eq(session_id: "abc-123-xyz")
    end

    it "ignores other system subtypes (only system/init carries the session_id we need)" do
      event = { type: "system", subtype: "other", session_id: "xxx" }.to_json
      update = invocation.send(:process_event, event, ->(l) { lines << l })
      expect(update).to be_nil
    end
  end

  describe "default_runner cmd line ordering" do
    # `claude --mcp-config <configs...>` is variadic and will swallow
    # the next positional arg as a second config. If `--mcp-config <path>`
    # ends up immediately before the prompt, claude prepends cwd to the
    # prompt and bails with ENAMETOOLONG. This regression test pins the
    # ordering: --mcp-config must always be followed by another flag,
    # never by the prompt directly.
    it "places --mcp-config before another flag, not directly before the prompt" do
      invocation = described_class.new("/tmp", prompt: "PROMPT_BODY", oauth_token: "x",
                                       mcp_config: "/tmp/mcp.json")

      cmd = []
      allow(Open3).to receive(:popen2e) do |_env, *args, **_opts, &blk|
        cmd.replace(args)
        rd, wr = IO.pipe
        wr.close
        fake_wait = Struct.new(:value, :pid).new(Struct.new(:exitstatus).new(0), 0)
        blk.call($stdin, rd, fake_wait)
        rd.close
      end

      invocation.run

      mcp_idx    = cmd.index("--mcp-config")
      prompt_idx = cmd.index("PROMPT_BODY")
      expect(mcp_idx).not_to be_nil, "expected --mcp-config in cmd: #{cmd.inspect}"
      expect(cmd[mcp_idx + 1]).to eq("/tmp/mcp.json")
      expect(cmd[mcp_idx + 2]).to start_with("--"),
        "arg after mcp-config path must be another flag, not a positional — got #{cmd[mcp_idx + 2].inspect}"
      expect(prompt_idx).to eq(cmd.length - 1)  # prompt is the last positional
    end

    it "passes --resume <id> when resume_session_id is set" do
      invocation = described_class.new("/tmp", prompt: "P", oauth_token: "x",
                                       resume_session_id: "abc-123")
      cmd = []
      allow(Open3).to receive(:popen2e) do |_env, *args, **_opts, &blk|
        cmd.replace(args)
        rd, wr = IO.pipe; wr.close
        fake_wait = Struct.new(:value, :pid).new(Struct.new(:exitstatus).new(0), 0)
        blk.call($stdin, rd, fake_wait)
        rd.close
      end

      invocation.run

      idx = cmd.index("--resume")
      expect(idx).not_to be_nil, "expected --resume in cmd: #{cmd.inspect}"
      expect(cmd[idx + 1]).to eq("abc-123")
      expect(cmd[idx + 2]).to start_with("--"), "arg after resume id must be another flag — got #{cmd[idx + 2].inspect}"
    end

    it "omits --resume when resume_session_id is nil (default)" do
      invocation = described_class.new("/tmp", prompt: "P", oauth_token: "x")
      cmd = []
      allow(Open3).to receive(:popen2e) do |_env, *args, **_opts, &blk|
        cmd.replace(args)
        rd, wr = IO.pipe; wr.close
        fake_wait = Struct.new(:value, :pid).new(Struct.new(:exitstatus).new(0), 0)
        blk.call($stdin, rd, fake_wait)
        rd.close
      end

      invocation.run
      expect(cmd).not_to include("--resume")
    end
  end
end
