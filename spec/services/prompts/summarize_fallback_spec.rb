require "rails_helper"

RSpec.describe Prompts::SummarizeFallback do
  let(:issue) { Struct.new(:title, :body).new("Add greeting", "We need a greeting helper.") }
  let(:diff)  { "diff --git a/feature.rb b/feature.rb\n+def greet = 'hi'\n" }

  it "asks the agent to call submit_summary without editing files" do
    out = described_class.new(issue: issue, diff: diff).to_s

    expect(out).to include("original agent session was too large to resume")
    expect(out).to include("submit_summary")
    expect(out).to include("exact prefixed name")
    expect(out).to include("Do not edit files, run commands, or make commits")
  end

  it "embeds bounded job context and diff context" do
    out = described_class.new(issue: issue, diff: diff).to_s

    expect(out).to include("Title: Add greeting")
    expect(out).to include("We need a greeting helper.")
    expect(out).to include("def greet = 'hi'")
  end

  it "truncates oversized bodies and diffs by safe UTF-8 byte boundaries" do
    big_issue = Struct.new(:title, :body).new("Add greeting", "●" * 10_000)
    big_diff = "●" * (described_class::MAX_DIFF_BYTES + 3_000)

    out = described_class.new(issue: big_issue, diff: big_diff).to_s

    expect(out).to include("[truncated")
    expect(out).to be_valid_encoding
  end
end
