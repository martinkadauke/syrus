require "rails_helper"

RSpec.describe Prompts::Initial do
  let(:issue) { Struct.new(:title, :body).new("Add greeting", "We need a greeting helper.") }

  it "joins title and body with a blank line" do
    expect(described_class.new(issue: issue).to_s).to eq("Add greeting\n\nWe need a greeting helper.")
  end

  it "strips leading/trailing whitespace" do
    padded_issue = Struct.new(:title, :body).new("  Add greeting  ", "  body  ")
    expect(described_class.new(issue: padded_issue).to_s).to eq("Add greeting  \n\n  body")
  end

  it "handles a nil body" do
    issue_no_body = Struct.new(:title, :body).new("Add greeting", nil)
    expect(described_class.new(issue: issue_no_body).to_s).to eq("Add greeting")
  end
end
