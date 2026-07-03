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

  it "includes Epic context between the issue content and safety footer when present" do
    epic = instance_double(
      Epic,
      slug: "EPIC-70",
      title: "Syrus CLI and test planning",
      description: "Coordinate the Ruby workflow step and Go CLI."
    )

    out = described_class.new(issue: issue, epic: epic).to_s

    issue_pos = out.index("Add greeting")
    epic_pos = out.index("EPIC-70: Syrus CLI and test planning")
    guard_pos = out.index("Do not implement the entire Epic")
    safety_pos = out.index(Prompts::GitSafety::TEXT)

    expect(issue_pos).to be < epic_pos
    expect(epic_pos).to be < safety_pos
    expect(guard_pos).to be < safety_pos
  end
end
