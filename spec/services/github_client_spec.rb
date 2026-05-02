require "rails_helper"

RSpec.describe GithubClient do
  let(:user) { Factories.user(github_token: "ghp_test_token") }

  it "raises when the user has no github_token" do
    bare = Factories.user
    expect { GithubClient.new(bare) }.to raise_error(ArgumentError)
  end

  describe "#issues_with_label", :vcr do
    it "lists labelled issues for a repo", vcr: { cassette_name: "poll_repository_job/lists_issues" } do
      issues = GithubClient.for(user).issues_with_label("acme/widgets", "syrus")
      numbers = issues.map(&:number)
      expect(numbers).to include(42, 43, 44, 45, 46)
    end
  end

  describe "#create_pull_request", :vcr do
    it "opens a PR through Octokit and returns the new resource",
       vcr: { cassette_name: "github_client/create_pull_request" } do
      pr = GithubClient.for(user).create_pull_request(
        "acme/widgets",
        base: "main",
        head: "syrus/issue-42-1",
        title: "hello",
        body: "there"
      )
      expect(pr.number).to eq(7)
      expect(pr.html_url).to eq("https://github.com/acme/widgets/pull/7")
    end
  end

  describe "#fetch_issue", :vcr do
    it "returns the issue title + body for prompt construction",
       vcr: { cassette_name: "github_client/fetch_issue" } do
      issue = GithubClient.for(user).fetch_issue("acme/widgets", 42)
      expect(issue.number).to eq(42)
      expect(issue.title).to eq("Add greeting helper")
      expect(issue.body).to match(/greeting helper/)
    end
  end
end
