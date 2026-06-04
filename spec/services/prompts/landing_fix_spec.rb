require "rails_helper"

RSpec.describe Prompts::LandingFix do
  it "frames the final merge-readiness pass for the current PR branch" do
    issue = Struct.new(:title, :body).new("Keep dashboard honest", "Run the final checks after rebasing.")

    output = described_class.new(
      issue: issue,
      pr_number: 123,
      repo_slug: "acme/widgets",
      branch_name: "syrus/issue-42-9",
      recent_commits: [ { sha: "abcdef123456", subject: "Fix dashboard state" } ]
    ).to_s

    expect(output).to include("final merge-readiness pass")
    expect(output).to include("acme/widgets#123")
    expect(output).to include("syrus/issue-42-9")
    expect(output).to include("Keep dashboard honest")
    expect(output).to include("abcdef1 Fix dashboard state")
    expect(output).to include("If there is no concrete problem to fix, make no code changes.")
    expect(output).to include(Prompts::GitSafety::TEXT)
  end
end
