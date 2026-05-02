require "rails_helper"

RSpec.describe PullRequestOpener do
  let(:user) { Factories.user(github_token: "ghp_test_token") }
  let(:repository) do
    Factories.repository(user: user, owner: "acme", name: "widgets", default_branch: "main")
  end

  it "delegates to GithubClient#create_pull_request and returns the new PR number" do
    fake_pr = double(number: 99)
    fake_client = instance_double(GithubClient, create_pull_request: fake_pr)

    opener = described_class.new(repository, client: fake_client)
    pr_number = opener.open(branch: "syrus/issue-1-1", title: "T", body: "B")

    expect(pr_number).to eq(99)
    expect(fake_client).to have_received(:create_pull_request).with(
      "acme/widgets",
      base: "main",
      head: "syrus/issue-1-1",
      title: "T",
      body: "B"
    )
  end
end
