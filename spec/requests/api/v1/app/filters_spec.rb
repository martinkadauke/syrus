require "rails_helper"

RSpec.describe "API: /api/v1/app/filters", type: :request do
  def parse_body
    JSON.parse(response.body)
  end

  it "401s with a JSON error when signed out" do
    get "/api/v1/app/filters/fk_options", params: { field: "job_id" }

    expect(response).to have_http_status(:unauthorized)
    expect(parse_body.dig("error", "code")).to eq("unauthorized")
  end

  it "returns normalized FK option payloads scoped to the current user" do
    user = Factories.user
    repo = Factories.repository(user: user)
    other_user = Factories.user
    other_repo = Factories.repository(user: other_user)
    own = Factories.job_record(user: user, repository: repo, issue_number: 42, issue_title: "Find me")
    Factories.job_record(user: other_user, repository: other_repo, issue_number: 43, issue_title: "Find me elsewhere")
    sign_in_as(user)

    get "/api/v1/app/filters/fk_options", params: { field: "job_id", q: "Find me" }

    expect(response).to have_http_status(:ok)
    expect(parse_body).to eq(
      "options" => [
        { "value" => own.id, "label" => "#42 Find me" }
      ]
    )
  end

  it "resolves explicit ids in bulk" do
    user = Factories.user
    repo = Factories.repository(user: user)
    old = Factories.job_record(user: user, repository: repo, issue_number: 7, issue_title: "Ancient task", created_at: 3.years.ago)
    recent = Factories.job_record(user: user, repository: repo, issue_number: 8, issue_title: "Recent task")
    sign_in_as(user)

    get "/api/v1/app/filters/fk_options", params: { field: "job_id", ids: [ old.id, recent.id ] }

    expect(response).to have_http_status(:ok)
    expect(parse_body["options"]).to contain_exactly(
      { "value" => old.id, "label" => "#7 Ancient task" },
      { "value" => recent.id, "label" => "#8 Recent task" }
    )
  end

  it "returns a structured error for unknown fields" do
    sign_in_as(Factories.user)

    get "/api/v1/app/filters/fk_options", params: { field: "user_id" }

    expect(response).to have_http_status(:bad_request)
    expect(parse_body.dig("error", "code")).to eq("unknown_field")
    expect(parse_body.dig("error", "message")).to eq("Unknown filter field.")
  end
end
