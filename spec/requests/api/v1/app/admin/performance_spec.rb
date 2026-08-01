require "rails_helper"

RSpec.describe "API: /api/v1/app/admin/performance", type: :request do
  let!(:admin) { Factories.user(admin: true) }
  let(:non_admin) { Factories.user(admin: false) }
  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

  def parse_body = JSON.parse(response.body)

  before do
    allow(Rails).to receive(:cache).and_return(cache_store)
    Feature.where(slug: "performance_logging").delete_all
    Feature.create!(slug: "performance_logging", category: "Operations", name: "Performance logging", enabled: true)
    Current.reset
    PerformanceLogging::Store.append(
      "event" => "syrus.performance.slow_phase",
      "phase" => "dashboard_payload",
      "duration_ms" => 700.0,
      "metadata" => { "view" => "jobs" },
      "occurred_at" => "2026-08-01T12:00:00Z"
    )
  end

  it "401s with a JSON error when signed out" do
    get "/api/v1/app/admin/performance"

    expect(response).to have_http_status(:unauthorized)
    expect(parse_body.dig("error", "code")).to eq("unauthorized")
  end

  it "403s with a JSON error for non-admin users" do
    sign_in_as(non_admin)

    get "/api/v1/app/admin/performance"

    expect(response).to have_http_status(:forbidden)
    expect(parse_body.dig("error", "code")).to eq("forbidden")
  end

  it "returns performance diagnostics for app admins" do
    sign_in_as(admin)

    get "/api/v1/app/admin/performance"

    expect(response).to have_http_status(:ok)
    body = parse_body
    expect(body["enabled"]).to eq(true)
    expect(body["events"].first).to include("event" => "syrus.performance.slow_phase", "phase" => "dashboard_payload")
    expect(body.dig("summaries", "slow_phases").first).to include(
      "phase" => "dashboard_payload",
      "count" => 1,
      "max_duration_ms" => 700.0,
      "recent_metadata" => { "view" => "jobs" }
    )
  end
end
