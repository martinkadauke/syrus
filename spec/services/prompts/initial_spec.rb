require "rails_helper"

RSpec.describe Prompts::Initial do
  let(:issue) { Struct.new(:title, :body).new("Add greeting", "We need a greeting helper.") }

  it "joins title and body with a blank line" do
    out = described_class.new(issue: issue).to_s
    expect(out).to start_with("Add greeting\n\nWe need a greeting helper.")
  end

  it "strips leading/trailing whitespace from the issue body" do
    padded_issue = Struct.new(:title, :body).new("  Add greeting  ", "  body  ")
    out = described_class.new(issue: padded_issue).to_s
    expect(out).to start_with("Add greeting  \n\n  body")
  end

  it "handles a nil body" do
    issue_no_body = Struct.new(:title, :body).new("Add greeting", nil)
    out = described_class.new(issue: issue_no_body).to_s
    expect(out).to start_with("Add greeting\n\n")
  end

  it "appends the submit_summary instruction" do
    out = described_class.new(issue: issue).to_s
    expect(out).to include("CALL THE `submit_summary` MCP TOOL")
    expect(out).to end_with(Prompts::SubmitSummaryInstructions::TEXT)
  end
end
