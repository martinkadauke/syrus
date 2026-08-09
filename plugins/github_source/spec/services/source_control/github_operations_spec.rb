require "rails_helper"

RSpec.describe SourceControl::GithubOperations do
  let(:user) { Factories.user(github_token: "ghp_user") }
  let(:repository) { Factories.repository(user: user, owner: "acme", name: "widgets") }

  it "identifies GitHub repositories by slug shape" do
    expect(described_class.provider_key).to eq("github")
    expect(described_class.display_name).to eq("GitHub")
    expect(described_class.available_for?(repository)).to be(true)
  end

  it "delegates client construction to GithubClient" do
    client = instance_double(GithubClient)

    expect(GithubClient).to receive(:for).with(repository: repository, user: user).and_return(client)

    expect(described_class.client_for(repository: repository, user: user)).to eq(client)
  end
end
