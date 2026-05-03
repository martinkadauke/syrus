require "rails_helper"

RSpec.describe Prompts::Resume do
  let(:out) { described_class.new.to_s }

  it "explains that the previous session was interrupted by a worker death" do
    expect(out).to match(/interrupted/i)
    expect(out).to match(/worker\s+process died/im)
  end

  it "warns that uncommitted edits are gone but committed work survived" do
    expect(out).to match(/uncommitted/i)
    expect(out).to match(/committed/i)
  end

  it "tells the agent to verify state with git status / git log" do
    expect(out).to include("git status")
    expect(out).to include("git log")
  end

  it "tells the agent NOT to redo work that's already committed" do
    expect(out).to match(/[Dd]o not redo/)
  end

  it "appends the submit_summary instruction so the MCP contract carries through" do
    expect(out).to end_with(Prompts::SubmitSummaryInstructions::TEXT)
  end
end
