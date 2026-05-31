require "rails_helper"

RSpec.describe "API: /api/v1/app/epics", type: :request do
  let(:user) { Factories.user }
  let(:repository) { Factories.repository(user: user, owner: "acme", name: "widgets") }

  def parse_body
    JSON.parse(response.body)
  end

  it "401s with a JSON error when signed out" do
    get "/api/v1/app/epics/new"

    expect(response).to have_http_status(:unauthorized)
    expect(parse_body.dig("error", "code")).to eq("unauthorized")
  end

  it "returns the new epic form payload with the user's repositories" do
    sign_in_as(user)
    repository
    Factories.repository(user: Factories.user, owner: "other", name: "private")

    get "/api/v1/app/epics/new"

    expect(response).to have_http_status(:ok)
    body = parse_body
    expect(body.dig("epic", "id")).to be_nil
    expect(body["repositories"]).to contain_exactly(include("id" => repository.id, "slug" => "acme/widgets"))
    expect(body.to_s).not_to include("other/private")
    expect(body["dashboard_epics_path"]).to eq(dashboard_epics_path)
  end

  it "returns the edit epic form payload" do
    sign_in_as(user)
    epic = Factories.epic(
      user: user,
      repository: repository,
      title: "Raise the forum",
      description: "Install tasteful columns.",
      github_issue_url: "https://github.com/acme/widgets/issues/12"
    )

    get "/api/v1/app/epics/#{epic.id}/edit"

    expect(response).to have_http_status(:ok)
    expect(parse_body["epic"]).to include(
      "id" => epic.id,
      "title" => "Raise the forum",
      "description" => "Install tasteful columns.",
      "repository_id" => repository.id,
      "github_issue_url" => "https://github.com/acme/widgets/issues/12",
      "epic_path" => epic_path(epic)
    )
  end

  it "creates an epic and returns its redirect path" do
    sign_in_as(user)

    expect {
      post "/api/v1/app/epics", params: {
        epic: {
          title: "Raise the forum",
          description: "Install tasteful columns.",
          repository_id: repository.id,
          github_issue_url: "https://github.com/acme/widgets/issues/12"
        }
      }
    }.to change { user.epics.count }.by(1)

    expect(response).to have_http_status(:created)
    epic = user.epics.order(:id).last
    expect(epic).to have_attributes(
      title: "Raise the forum",
      description: "Install tasteful columns.",
      repository_id: repository.id,
      github_issue_url: "https://github.com/acme/widgets/issues/12"
    )
    expect(parse_body).to include(
      "message" => "Epic created.",
      "redirect_to" => epic_path(epic)
    )
  end

  it "returns validation errors without creating an epic" do
    sign_in_as(user)

    expect {
      post "/api/v1/app/epics", params: {
        epic: {
          title: "",
          repository_id: repository.id
        }
      }
    }.not_to change { user.epics.count }

    expect(response).to have_http_status(:unprocessable_content)
    expect(parse_body.dig("error", "code")).to eq("validation_failed")
    expect(parse_body.dig("error", "message")).to include("Title can't be blank")
  end

  it "updates an epic" do
    sign_in_as(user)
    epic = Factories.epic(user: user, repository: repository, title: "Raise the forum")
    other_repo = Factories.repository(user: user, owner: "acme", name: "marble")

    patch "/api/v1/app/epics/#{epic.id}", params: {
      epic: {
        title: "Raise the basilica",
        description: "Install louder columns.",
        repository_id: other_repo.id,
        github_issue_url: "https://github.com/acme/marble/issues/7"
      }
    }

    expect(response).to have_http_status(:ok)
    expect(epic.reload).to have_attributes(
      title: "Raise the basilica",
      description: "Install louder columns.",
      repository_id: other_repo.id,
      github_issue_url: "https://github.com/acme/marble/issues/7"
    )
    expect(parse_body).to include("message" => "Epic updated.", "redirect_to" => epic_path(epic))
  end

  it "does not expose another user's epic" do
    sign_in_as(user)
    other_user = Factories.user
    other_repo = Factories.repository(user: other_user)
    epic = Factories.epic(user: other_user, repository: other_repo, title: "Private aqueduct")

    get "/api/v1/app/epics/#{epic.id}/edit"
    expect(response).to have_http_status(:not_found)

    patch "/api/v1/app/epics/#{epic.id}", params: { epic: { title: "Rename it", repository_id: repository.id } }
    expect(response).to have_http_status(:not_found)
    expect(epic.reload.title).to eq("Private aqueduct")
  end
end
