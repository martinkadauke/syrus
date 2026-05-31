require "rails_helper"

RSpec.describe "API: /api/v1/app/repositories", type: :request do
  let(:user) { Factories.user }

  def parse_body
    JSON.parse(response.body)
  end

  it "401s with a JSON error when signed out" do
    get "/api/v1/app/repositories"

    expect(response).to have_http_status(:unauthorized)
    expect(parse_body.dig("error", "code")).to eq("unauthorized")
  end

  it "lists active and archived repositories for the signed-in user" do
    sign_in_as(user)
    active = Factories.repository(
      user: user,
      owner: "acme",
      name: "widgets",
      default_branch: "main",
      trigger_label: "syrus",
      polling_enabled: true,
      agent_provider: "codex",
      last_poll_status: "ok",
      last_poll_started_at: Time.zone.parse("2026-05-30 12:00:00")
    )
    archived = Factories.repository(user: user, owner: "old", name: "repo")
    archived.archive!
    Factories.repository(user: Factories.user, owner: "other", name: "private")

    get "/api/v1/app/repositories"

    expect(response).to have_http_status(:ok)
    body = parse_body
    expect(body["active_repositories"]).to contain_exactly(
      include(
        "id" => active.id,
        "slug" => "acme/widgets",
        "default_branch" => "main",
        "trigger_label" => "syrus",
        "polling_enabled" => true,
        "agent_provider_label" => "Codex",
        "last_poll_status" => "ok",
        "repository_path" => repository_path(active),
        "edit_repository_path" => edit_repository_path(active)
      )
    )
    expect(body["archived_repositories"]).to contain_exactly(
      include("id" => archived.id, "slug" => "old/repo", "archived" => true)
    )
    expect(body.to_s).not_to include("other/private")
    expect(body["new_repository_path"]).to eq(new_repository_path)
  end

  it "returns the new repository form payload" do
    sign_in_as(user)
    user.update!(agent_provider: "codex")

    get "/api/v1/app/repositories/new"

    expect(response).to have_http_status(:ok)
    body = parse_body
    expect(body.dig("repository", "default_branch")).to eq("main")
    expect(body.dig("repository", "trigger_label")).to eq("syrus")
    expect(body.dig("repository", "polling_enabled")).to eq(true)
    expect(body["configured_agent_providers"]).to include(
      { "value" => "codex", "label" => "Codex" },
      { "value" => "claude", "label" => "Claude Code" }
    )
    expect(body["user_agent_provider_label"]).to eq("Codex")
    expect(body["auto_approve_modes"]).to include(include("value" => "if_graders_pass"))
    expect(body["repositories_path"]).to eq(repositories_path)
  end

  it "returns the edit repository form payload" do
    sign_in_as(user)
    repository = Factories.repository(
      user: user,
      owner: "acme",
      name: "widgets",
      default_branch: "trunk",
      trigger_label: "delegate",
      polling_enabled: false,
      prepare_enabled: false,
      pr_cost_footer_enabled: false,
      auto_merge_enabled: true,
      agent_provider: "codex",
      auto_approve_mode: "if_graders_pass",
      github_owner_id: 123,
      github_repository_id: 456
    )

    get "/api/v1/app/repositories/#{repository.id}/edit"

    expect(response).to have_http_status(:ok)
    expect(parse_body["repository"]).to include(
      "id" => repository.id,
      "owner" => "acme",
      "name" => "widgets",
      "slug" => "acme/widgets",
      "default_branch" => "trunk",
      "trigger_label" => "delegate",
      "polling_enabled" => false,
      "prepare_enabled" => false,
      "pr_cost_footer_enabled" => false,
      "auto_merge_enabled" => true,
      "agent_provider" => "codex",
      "auto_approve_mode" => "if_graders_pass",
      "github_owner_id" => 123,
      "github_repository_id" => 456,
      "repository_path" => repository_path(repository)
    )
  end

  it "returns the repository detail payload" do
    sign_in_as(user)
    AppSetting.current.update!(github_app_id: 123, github_app_slug: "operator-syrus")
    repository = Factories.repository(
      user: user,
      owner: "acme",
      name: "widgets",
      trigger_label: "syrus",
      agent_provider: "codex",
      github_owner_id: 100,
      github_repository_id: 200
    )
    active_note = repository.repository_notes.create!(body: "Use staging for smoke tests.", author: "operator")
    repository.repository_notes.create!(body: "Removed context.", author: "agent", removed_at: Time.current)
    failed = Factories.job(repository: repository, issue_number: 1, issue_title: "Fix forum")
    failed.current_run.update!(state: "failed", finished_at: Time.current)
    running = Factories.job(repository: repository, issue_number: 2, issue_title: "Survey aqueduct")
    running.current_run.update!(state: "running", started_at: Time.current)
    queued = Factories.job(repository: repository, issue_number: 3, issue_title: "Polish marble")
    queued.current_run.update!(state: "queued")
    other_repository = Factories.repository(user: user, owner: "acme", name: "other")
    Factories.job(repository: other_repository, issue_number: 99, issue_title: "Private")

    get "/api/v1/app/repositories/#{repository.id}"

    expect(response).to have_http_status(:ok)
    body = parse_body
    expect(body.dig("repository", "slug")).to eq("acme/widgets")
    expect(body.dig("repository", "agent_provider_label")).to eq("Codex")
    expect(body.dig("repository", "github_url")).to eq("https://github.com/acme/widgets")
    expect(body["tabs"]).to include(
      { "key" => "overview", "label" => "Overview", "path" => repository_path(repository) },
      { "key" => "github_issues", "label" => "GitHub Issues", "path" => repository_path(repository, tab: "github_issues") },
      { "key" => "scheduled_tasks", "label" => "Scheduled Tasks", "path" => repository_scheduled_tasks_path(repository) }
    )
    expect(body["counts"]).to include("running" => 1, "queued" => 1, "failed_7d" => 1)
    expect(body["retry_failed_jobs"]).to include("count" => 1, "agent_provider_label" => "Codex")
    expect(body["credential_status"]).to include(
      "mode" => "pat",
      "github_app_registered" => true,
      "install_url" => "https://github.com/apps/operator-syrus/installations/new/permissions?target_id=100&repository_ids[]=200"
    )
    expect(body["notes"]).to contain_exactly(include(
      "id" => active_note.id,
      "body" => "Use staging for smoke tests.",
      "delete_path" => repository_note_path(repository, active_note)
    ))
    expect(body["jobs"]).to include(
      include("id" => failed.id, "issue_title" => "Fix forum", "source" => include("label" => "#1")),
      include("id" => running.id, "issue_title" => "Survey aqueduct"),
      include("id" => queued.id, "issue_title" => "Polish marble")
    )
    expect(body.to_s).not_to include("Private")
    expect(body["pagination"]).to include("page" => 1, "total_jobs" => 3, "total_pages" => 1)
    expect(body["paths"]).to include(
      "new_job_path" => new_job_path(repository_id: repository.id),
      "edit_repository_path" => edit_repository_path(repository),
      "repository_notes_path" => repository_notes_path(repository)
    )
  end

  it "does not expose another user's repository detail" do
    sign_in_as(user)
    foreign = Factories.repository(user: Factories.user)

    get "/api/v1/app/repositories/#{foreign.id}"

    expect(response).to have_http_status(:not_found)
  end

  it "creates repositories" do
    sign_in_as(user)

    expect {
      post "/api/v1/app/repositories", params: {
        repository: {
          owner: "acme",
          name: "widgets",
          default_branch: "main",
          trigger_label: "syrus",
          polling_enabled: "1",
          prepare_enabled: "0",
          pr_cost_footer_enabled: "0",
          auto_merge_enabled: "1",
          agent_provider: "codex",
          auto_approve_mode: "if_graders_pass",
          github_owner_id: "123",
          github_repository_id: "456"
        }
      }
    }.to change(user.repositories, :count).by(1)

    expect(response).to have_http_status(:created)
    repository = user.repositories.last
    expect(repository.slug).to eq("acme/widgets")
    expect(repository.prepare_enabled).to eq(false)
    expect(repository.pr_cost_footer_enabled).to eq(false)
    expect(repository.auto_merge_enabled).to eq(true)
    expect(repository.agent_provider).to eq("codex")
    expect(repository.auto_approve_mode).to eq("if_graders_pass")
    expect(repository.github_owner_id).to eq(123)
    expect(repository.github_repository_id).to eq(456)
    expect(parse_body).to include("message" => "Repository acme/widgets added.", "redirect_to" => repositories_path)
  end

  it "returns validation errors when create fails" do
    sign_in_as(user)

    expect {
      post "/api/v1/app/repositories", params: {
        repository: {
          owner: "bad owner",
          name: "",
          default_branch: "",
          trigger_label: ""
        }
      }
    }.not_to change(user.repositories, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(parse_body.dig("error", "code")).to eq("validation_failed")
    expect(parse_body.dig("error", "message")).to include("Owner")
  end

  it "updates repositories" do
    sign_in_as(user)
    repository = Factories.repository(user: user, owner: "acme", name: "widgets")

    patch "/api/v1/app/repositories/#{repository.id}", params: {
      repository: {
        owner: "acme",
        name: "widgets",
        default_branch: "trunk",
        trigger_label: "delegate",
        polling_enabled: "0",
        prepare_enabled: "0",
        pr_cost_footer_enabled: "0",
        auto_merge_enabled: "1",
        agent_provider: "codex",
        auto_approve_mode: "if_graders_pass_and_tagged_safe",
        github_owner_id: "123",
        github_repository_id: "456"
      }
    }

    expect(response).to have_http_status(:ok)
    expect(repository.reload.default_branch).to eq("trunk")
    expect(repository.trigger_label).to eq("delegate")
    expect(repository.polling_enabled).to eq(false)
    expect(repository.prepare_enabled).to eq(false)
    expect(repository.pr_cost_footer_enabled).to eq(false)
    expect(repository.auto_merge_enabled).to eq(true)
    expect(repository.agent_provider).to eq("codex")
    expect(repository.auto_approve_mode).to eq("if_graders_pass_and_tagged_safe")
    expect(repository.github_owner_id).to eq(123)
    expect(repository.github_repository_id).to eq(456)
    expect(parse_body).to include("message" => "Repository acme/widgets updated.", "redirect_to" => repositories_path)
  end

  it "enqueues a forced poll and returns the refreshed index payload" do
    sign_in_as(user)
    repository = Factories.repository(user: user, owner: "acme", name: "widgets")

    expect {
      post "/api/v1/app/repositories/#{repository.id}/poll"
    }.to have_enqueued_job(PollRepositoryJob).with(repository.id, force: true)

    expect(response).to have_http_status(:ok)
    expect(parse_body["message"]).to eq("Polling acme/widgets now.")
    expect(parse_body.dig("active_repositories", 0, "slug")).to eq("acme/widgets")
  end

  it "rejects polling an archived repository" do
    sign_in_as(user)
    repository = Factories.repository(user: user)
    repository.archive!

    expect {
      post "/api/v1/app/repositories/#{repository.id}/poll"
    }.not_to have_enqueued_job(PollRepositoryJob)

    expect(response).to have_http_status(:unprocessable_content)
    expect(parse_body.dig("error", "code")).to eq("validation_failed")
    expect(parse_body.dig("error", "message")).to include("archived")
  end

  it "archives and unarchives repositories" do
    sign_in_as(user)
    repository = Factories.repository(user: user, owner: "acme", name: "widgets", polling_enabled: true)

    post "/api/v1/app/repositories/#{repository.id}/archive"

    expect(response).to have_http_status(:ok)
    expect(repository.reload).to be_archived
    expect(repository.polling_enabled).to eq(false)
    expect(parse_body["message"]).to eq("acme/widgets archived.")
    expect(parse_body.dig("archived_repositories", 0, "slug")).to eq("acme/widgets")

    post "/api/v1/app/repositories/#{repository.id}/unarchive"

    expect(response).to have_http_status(:ok)
    expect(repository.reload).not_to be_archived
    expect(parse_body["message"]).to include("unarchived")
    expect(parse_body.dig("active_repositories", 0, "slug")).to eq("acme/widgets")
  end

  it "does not expose another user's repository commands" do
    sign_in_as(user)
    foreign = Factories.repository(user: Factories.user)

    post "/api/v1/app/repositories/#{foreign.id}/archive"

    expect(response).to have_http_status(:not_found)
    expect(foreign.reload).not_to be_archived
  end

  it "does not expose another user's repository form" do
    sign_in_as(user)
    foreign = Factories.repository(user: Factories.user)

    get "/api/v1/app/repositories/#{foreign.id}/edit"

    expect(response).to have_http_status(:not_found)
  end

  it "returns GitHub owners for repository selectors" do
    sign_in_as(user)
    allow(GithubClient).to receive(:for_user).and_return(
      instance_double(GithubClient, accessible_owners: { user: "john", orgs: %w[org-a] })
    )

    get "/api/v1/app/repositories/owners"

    expect(response).to have_http_status(:ok)
    expect(parse_body).to eq("user" => "john", "orgs" => [ "org-a" ])
  end

  it "returns no_token for owner selectors without GitHub credentials" do
    sign_in_as(user)
    allow(GithubClient).to receive(:for_user).and_raise(ArgumentError)

    get "/api/v1/app/repositories/owners"

    expect(response).to have_http_status(:ok)
    expect(parse_body).to eq("error" => "no_token")
  end

  it "returns repositories for a selected owner" do
    sign_in_as(user)
    allow(GithubClient).to receive(:for_user).and_return(
      instance_double(
        GithubClient,
        owner_repos: [
          { name: "alpha", github_repository_id: 456, github_owner_id: 123 },
          { name: "beta", github_repository_id: 789, github_owner_id: 123 }
        ]
      )
    )

    get "/api/v1/app/repositories/repos", params: { owner: "john", owner_type: "user" }

    expect(response).to have_http_status(:ok)
    expect(parse_body["repos"]).to contain_exactly(
      { "name" => "alpha", "github_repository_id" => 456, "github_owner_id" => 123 },
      { "name" => "beta", "github_repository_id" => 789, "github_owner_id" => 123 }
    )
  end

  it "returns branches for a selected repository" do
    sign_in_as(user)
    allow(GithubClient).to receive(:for_user).and_return(
      instance_double(GithubClient, repo_branches: { branches: %w[main trunk], default_branch: "main" })
    )

    get "/api/v1/app/repositories/branches", params: { owner: "john", name: "alpha" }

    expect(response).to have_http_status(:ok)
    expect(parse_body).to eq("branches" => [ "main", "trunk" ], "default_branch" => "main")
  end
end
