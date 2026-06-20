require "rails_helper"

RSpec.describe Prompts::ChatOnboarding do
  it "scripts welcome, explanation, Epic proposal, and the landing rule" do
    out = described_class.new.to_s

    expect(out).to include("FIRST-RUN ONBOARDING")
    expect(out).to include("WELCOME")
    expect(out).to match(/A \*\*Job\*\* is one thread of work/)
    expect(out).to match(/An \*\*Epic\*\* is a named group/)
    expect(out).to include("propose_epic_with_jobs")
    expect(out).to include("AGENTS.md")
    expect(out).to include(".syrus.yml")
    expect(out).to include("In Progress")
    expect(out).to include("every** child")
    expect(out).to include("Onboarding is complete when the Epic lands")
  end

  it "names the connected repository in the welcome when present" do
    repo = repository(owner: "acme", name: "widgets")

    expect(described_class.new(repository: repo).to_s).to include("acme/widgets")
  end
end
