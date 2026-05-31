require "rails_helper"

RSpec.describe "App API job source browser", type: :request do
  let(:user) { Factories.user }
  let(:repo) { Factories.repository(user: user, owner: "acme", name: "widgets", default_branch: "main") }
  let(:job) { Factories.job(repository: repo, issue_number: 42, branch_name: "syrus/issue-42") }

  before { sign_in_as(user) }

  def parse_body = JSON.parse(response.body)

  it "returns a source error without touching GitHub when credentials are missing" do
    user.update!(github_token: nil)

    expect(GithubClient).not_to receive(:for)

    get "/api/v1/app/jobs/#{job.id}/source"

    expect(response).to have_http_status(:ok)
    body = parse_body
    expect(body["job_id"]).to eq(job.id)
    expect(body["source_error"]).to eq("GitHub token not configured. Add one in Settings to browse source.")
    expect(body["tree_items"]).to eq([])
    expect(body["file"]).to be_nil
    expect(body.dig("paths", "app_source_path")).to eq("/api/v1/app/jobs/#{job.id}/source")
  end

  it "returns refs, compact tree items, and selected file content" do
    user.update!(github_token: "ghp_test_token")
    commit_sha = "deadbeef12345678"
    github = instance_double(GithubClient)

    allow(GithubClient).to receive(:for).with(repository: repo, user: user).and_return(github)
    allow(github).to receive(:compare_commits)
      .with("acme/widgets", "main", "syrus/issue-42")
      .and_return(
        commits: [
          {
            sha: commit_sha,
            short_sha: "deadbee",
            message: "Change user model",
            date: Time.zone.parse("2026-05-01T12:00:00Z")
          }
        ],
        merge_base_sha: "aabbccdd1234567"
      )
    allow(github).to receive(:file_tree_at)
      .with("acme/widgets", commit_sha)
      .and_return(
        items: [
          { path: "app/models/user.rb", size: 512 },
          { path: "app/frontend/routes/Chat.tsx", size: 256 },
          { path: "README.md", size: 128 }
        ],
        truncated: false
      )
    allow(github).to receive(:file_content_at)
      .with("acme/widgets", "app/models/user.rb", commit_sha)
      .and_return(content: "class User\nend\n", size: 15)

    get "/api/v1/app/jobs/#{job.id}/source", params: { path: "app/models/user.rb" }

    expect(response).to have_http_status(:ok)
    body = parse_body
    expect(body["selected_ref"]).to eq(commit_sha)
    expect(body["merge_base_sha"]).to eq("aabbccdd1234567")
    expect(body["branch_commits"]).to contain_exactly(include(
      "sha" => commit_sha,
      "short_sha" => "deadbee",
      "message" => "Change user model",
      "date" => "2026-05-01T12:00:00Z"
    ))
    expect(body["tree_items"]).to contain_exactly(
      include("path" => "app/models/user.rb", "name" => "user.rb", "language" => "ruby", "size" => 512),
      include("path" => "app/frontend/routes/Chat.tsx", "name" => "Chat.tsx", "language" => "typescript", "size" => 256),
      include("path" => "README.md", "name" => "README.md", "language" => "markdown", "size" => 128)
    )
    expect(body["tree_truncated"]).to eq(false)
    expect(body["source_error"]).to be_nil
    expect(body["file_error"]).to be_nil
    expect(body["file"]).to include(
      "path" => "app/models/user.rb",
      "name" => "user.rb",
      "language" => "ruby",
      "content" => "class User\nend\n",
      "size" => 15
    )
  end

  it "uses the default branch without comparing when the job has no branch" do
    user.update!(github_token: "ghp_test_token")
    job.update!(branch_name: nil)
    github = instance_double(GithubClient)

    allow(GithubClient).to receive(:for).with(repository: repo, user: user).and_return(github)
    expect(github).not_to receive(:compare_commits)
    allow(github).to receive(:file_tree_at)
      .with("acme/widgets", "main")
      .and_return(items: [ { path: "README.md", size: 64 } ], truncated: true)

    get "/api/v1/app/jobs/#{job.id}/source"

    expect(response).to have_http_status(:ok)
    body = parse_body
    expect(body["selected_ref"]).to eq("main")
    expect(body["tree_truncated"]).to eq(true)
    expect(body["tree_items"]).to contain_exactly(include("path" => "README.md", "language" => "markdown"))
  end

  it "does not expose another user's job" do
    other_user = Factories.user
    other_repo = Factories.repository(user: other_user, owner: "globex", name: "private")
    other_job = Factories.job(repository: other_repo, issue_number: 99)

    get "/api/v1/app/jobs/#{other_job.id}/source"

    expect(response).to have_http_status(:not_found)
  end
end
