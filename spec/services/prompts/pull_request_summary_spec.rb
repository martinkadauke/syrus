require "rails_helper"

RSpec.describe Prompts::PullRequestSummary do
  let(:issue) { Struct.new(:title, :body).new("Add greeting", "We need a greeting helper.") }
  let(:diff)  { "diff --git a/feature.rb b/feature.rb\n+def greet = 'hi'\n" }

  it "embeds the issue title, body, and diff in the prompt" do
    out = described_class.new(issue: issue, diff: diff).to_s
    expect(out).to include("Title: Add greeting")
    expect(out).to include("We need a greeting helper.")
    expect(out).to include("def greet = 'hi'")
  end

  it "instructs the agent to emit a single JSON object and nothing else, in CAPS" do
    out = described_class.new(issue: issue, diff: diff).to_s
    expect(out).to include("RESPOND WITH A SINGLE JSON OBJECT AND NOTHING ELSE")
    expect(out).to include('"title"').and include('"body"')
  end

  it "shows '(empty)' when the issue body is blank" do
    blank_issue = Struct.new(:title, :body).new("Add greeting", "")
    out = described_class.new(issue: blank_issue, diff: diff).to_s
    expect(out).to include("(empty)")
  end

  it "shows '(empty)' when the issue body is nil" do
    nil_issue = Struct.new(:title, :body).new("Add greeting", nil)
    out = described_class.new(issue: nil_issue, diff: diff).to_s
    expect(out).to include("(empty)")
  end

  it "passes a small diff through verbatim" do
    out = described_class.new(issue: issue, diff: diff).to_s
    expect(out).to include(diff)
    expect(out).not_to include("[truncated")
  end

  it "truncates an oversized diff and notes how many bytes were dropped" do
    big_diff = "x" * (described_class::MAX_DIFF_BYTES + 5_000)
    out = described_class.new(issue: issue, diff: big_diff).to_s

    expect(out.bytesize).to be < big_diff.bytesize + 2_000  # not the whole thing
    expect(out).to include("[truncated, 5000 more bytes]")
  end
end
