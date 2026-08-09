require "rails_helper"

RSpec.describe "API: /api/v1/admin/reconciler_activity", type: :request do
  let(:admin) { Factories.user }
  let(:admin_token) { admin.generate_api_token! }
  def auth = { "Authorization" => "Bearer #{admin_token}" }
  def parse_body = JSON.parse(response.body)

  it "requires an admin API token" do
    get "/api/v1/admin/reconciler_activity"

    expect(response).to have_http_status(:unauthorized)
  end

  it "returns reconciler activity for admin API clients" do
    WorkEngineReconcilerActivityEvent.record!(
      event_type: "run_finished",
      source: "spec",
      message: "Reconciler finished: 0 issue(s), 0 plan(s), 0 execution(s).",
      details: { issues_count: 0 }
    )

    get "/api/v1/admin/reconciler_activity", headers: auth

    expect(response).to have_http_status(:ok)
    expect(parse_body["events"].first).to include(
      "event_type" => "run_finished",
      "source" => "spec",
      "details" => include("issues_count" => 0)
    )
  end
end
