require "rails_helper"

RSpec.describe ForkSyncService do
  let(:user) { Factories.user }
  let(:upstream) { Factories.repository(user: user, owner: "upstream-org", name: "project") }
  let(:fork_repo) do
    Factories.repository(user: user, owner: "fork-user", name: "project", upstream_repository: upstream)
  end

  let(:client) { instance_double(GithubClient) }

  around do |example|
    original = ForkSyncService.client_factory
    ForkSyncService.client_factory = ->(_repo) { client }
    example.run
    ForkSyncService.client_factory = original
  end

  it "merges upstream into the fork's default branch and reports the merge type" do
    result_resource = Struct.new(:merge_type, :base_branch, :message).new("fast-forward", "main", "ok")
    expect(client).to receive(:merge_upstream).with("fork-user/project", fork_repo.default_branch).and_return(result_resource)

    result = described_class.call(repository: fork_repo)

    expect(result).to be_synced
    expect(result.merge_type).to eq("fast-forward")
  end

  it "returns :not_syncable for a repository without an in-instance upstream" do
    plain = Factories.repository(user: user, owner: "solo", name: "app")
    expect(client).not_to receive(:merge_upstream)

    result = described_class.call(repository: plain)

    expect(result.status).to eq(:not_syncable)
    expect(result).not_to be_synced
  end

  it "maps a merge conflict to :conflict without raising" do
    allow(client).to receive(:merge_upstream).and_raise(Octokit::Conflict.new)

    result = described_class.call(repository: fork_repo)

    expect(result.status).to eq(:conflict)
  end

  it "maps a non-syncable GitHub response (422) to :not_syncable" do
    allow(client).to receive(:merge_upstream).and_raise(Octokit::UnprocessableEntity.new)

    result = described_class.call(repository: fork_repo)

    expect(result.status).to eq(:not_syncable)
  end
end
