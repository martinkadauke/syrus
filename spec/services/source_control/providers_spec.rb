require "rails_helper"

RSpec.describe SourceControl::Providers do
  it "returns enabled source-control providers" do
    expect(described_class.all).to include(SourceControl::GithubOperations)
  end

  it "selects the first provider that accepts the repository" do
    repository = Factories.repository(owner: "acme", name: "widgets")

    expect(described_class.for_repository(repository)).to eq(SourceControl::GithubOperations)
  end
end
