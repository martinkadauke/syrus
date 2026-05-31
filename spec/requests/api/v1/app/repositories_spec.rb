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
end
