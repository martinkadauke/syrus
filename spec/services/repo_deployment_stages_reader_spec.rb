require "rails_helper"

RSpec.describe RepoDeploymentStagesReader do
  let(:user) { Factories.user(github_token: "ghp_test") }
  let(:repository) { Factories.repository(user: user, owner: "acme", name: "widgets", default_branch: "main") }
  let(:client) { GithubClient.allocate }

  before do
    described_class.clear_cache!
  end

  after do
    described_class.clear_cache!
  end

  it "returns a disabled plan without touching GitHub when credentials are unavailable" do
    user.update!(github_token: nil)
    expect(GithubClient).not_to receive(:for)

    result = described_class.new(repository: repository, user: user).resolve

    expect(result).not_to be_enabled
    expect(result.note).to eq("no GitHub credentials")
  end

  it "returns deployment stages from .syrus.yml" do
    allow(client).to receive(:file_content_at)
      .with("acme/widgets", ".syrus.yml", "main")
      .and_return(content: <<~YAML, size: 80)
        deployment_stages:
          - name: staging
            label: Staging
            tag: staging
      YAML

    result = described_class.new(repository: repository, user: user, client: client).resolve

    expect(result).to be_enabled
    expect(result.stages.first.name).to eq("staging")
  end

  it "caches repository lookups within the process TTL" do
    allow(GithubClient).to receive(:for).with(repository: repository, user: user).and_return(client)
    expect(client).to receive(:file_content_at).once.and_return(content: <<~YAML, size: 80)
      deployment_stages:
        - name: staging
          label: Staging
          tag: staging
    YAML

    first = described_class.for_repository(repository)
    second = described_class.for_repository(repository)

    expect(first).to be_enabled
    expect(second.stages.first.name).to eq("staging")
  end

  it "can bypass the process cache" do
    allow(GithubClient).to receive(:for).with(repository: repository, user: user).and_return(client)
    expect(client).to receive(:file_content_at).twice.and_return(
      { content: "deployment_stages:\n  - name: staging\n    tag: staging\n", size: 60 }
    )

    described_class.for_repository(repository, cached: false)
    described_class.for_repository(repository, cached: false)
  end
end
