require "rails_helper"

RSpec.describe PrSummarizer do
  let(:issue) { Struct.new(:title, :body).new("Add greeting helper", "We need a greeting helper.") }
  let(:diff)  { "diff --git a/feature.rb b/feature.rb\n+def greet = 'hi'\n" }

  def fake_runner_returning(text, **overrides)
    defaults = { turns: 1, exit_status: 0, timed_out: false, is_error: false, outcome: "success" }
    ->(**_) { AgentInvocation::Result.new(**defaults.merge(overrides), final_text: text) }
  end

  def call(runner:)
    described_class.new(issue: issue, diff: diff, oauth_token: "oat-x", runner: runner).call
  end

  describe "#call (success paths)" do
    it "parses a clean JSON object into title + body" do
      result = call(runner: fake_runner_returning(
        '{"title":"Add greeting helper","body":"Adds a tiny greet helper."}'
      ))
      expect(result).to be_success
      expect(result.title).to eq("Add greeting helper")
      expect(result.body).to eq("Adds a tiny greet helper.")
    end

    it "strips a surrounding ```json fence the agent sometimes adds" do
      result = call(runner: fake_runner_returning(
        "```json\n{\"title\":\"Fix typo\",\"body\":\"Fixes a typo in greet.\"}\n```"
      ))
      expect(result).to be_success
      expect(result.title).to eq("Fix typo")
      expect(result.body).to eq("Fixes a typo in greet.")
    end

    it "strips a bare ``` fence (no json language tag)" do
      result = call(runner: fake_runner_returning(
        "```\n{\"title\":\"Fix typo\",\"body\":\"Fixes a typo.\"}\n```"
      ))
      expect(result).to be_success
      expect(result.title).to eq("Fix typo")
    end

    it "preserves embedded \\n in the body" do
      result = call(runner: fake_runner_returning(
        '{"title":"Add greeting helper","body":"para 1\nbody\n\npara 2"}'
      ))
      expect(result).to be_success
      expect(result.body).to eq("para 1\nbody\n\npara 2")
    end
  end

  describe "#call (failure paths)" do
    it "returns failure when the JSON does not parse" do
      result = call(runner: fake_runner_returning("totally not json"))
      expect(result).not_to be_success
      expect(result.error).to match(/invalid JSON/)
    end

    it "returns failure when the title is empty" do
      result = call(runner: fake_runner_returning('{"title":"","body":"x"}'))
      expect(result).not_to be_success
      expect(result.error).to eq("empty title")
    end

    it "returns failure when the title is excessively long" do
      result = call(runner: fake_runner_returning(
        { title: "A" * 200, body: "x" }.to_json
      ))
      expect(result).not_to be_success
      expect(result.error).to match(/title too long/)
    end

    it "returns failure when the agent timed out" do
      runner = ->(**_) {
        AgentInvocation::Result.new(turns: 1, exit_status: nil, timed_out: true,
                                    is_error: false, outcome: nil, final_text: nil)
      }
      result = call(runner: runner)
      expect(result).not_to be_success
      expect(result.error).to match(/timed out/)
    end

    it "returns failure when the agent reported is_error" do
      runner = ->(**_) {
        AgentInvocation::Result.new(turns: 1, exit_status: 0, timed_out: false,
                                    is_error: true, outcome: "error_max_turns", final_text: nil)
      }
      result = call(runner: runner)
      expect(result).not_to be_success
      expect(result.error).to match(/error_max_turns/)
    end

    it "returns failure when the agent exited non-zero" do
      runner = ->(**_) {
        AgentInvocation::Result.new(turns: 1, exit_status: 2, timed_out: false,
                                    is_error: false, outcome: nil, final_text: nil)
      }
      result = call(runner: runner)
      expect(result).not_to be_success
      expect(result.error).to match(/exited 2/)
    end

    it "returns failure when final_text is blank" do
      result = call(runner: fake_runner_returning(""))
      expect(result).not_to be_success
      expect(result.error).to eq("empty response")
    end

    it "rescues unexpected exceptions and returns a failure Result" do
      runner = ->(**_) { raise "boom" }
      result = call(runner: runner)
      expect(result).not_to be_success
      expect(result.error).to match(/RuntimeError: boom/)
    end
  end

  describe "subprocess wiring" do
    it "pins the agent invocation to a single turn" do
      seen = {}
      runner = ->(**kwargs) {
        seen.merge!(kwargs)
        AgentInvocation::Result.new(turns: 1, exit_status: 0, timed_out: false, is_error: false,
                                    outcome: "success", final_text: '{"title":"x","body":"y"}')
      }
      described_class.new(issue: issue, diff: diff, oauth_token: "oat-x", runner: runner).call
      expect(seen[:max_turns]).to eq(1)
    end

    it "runs in a tmpdir, not against the operator's checkout" do
      seen_path = nil
      runner = ->(**kwargs) {
        seen_path = kwargs[:workspace_path]
        AgentInvocation::Result.new(turns: 1, exit_status: 0, timed_out: false, is_error: false,
                                    outcome: "success", final_text: '{"title":"x","body":"y"}')
      }
      described_class.new(issue: issue, diff: diff, oauth_token: "oat-x", runner: runner).call
      expect(seen_path).to start_with(Dir.tmpdir)
    end
  end
end
