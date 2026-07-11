require "rails_helper"

RSpec.describe "API: /api/v1/admin/performance", type: :request do
  let!(:admin) { Factories.user }
  let!(:admin_token) { admin.generate_api_token! }
  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

  def auth = { "Authorization" => "Bearer #{admin_token}" }
  def parse_body = JSON.parse(response.body)

  before do
    allow(Rails).to receive(:cache).and_return(cache_store)
    Feature.where(slug: "performance_logging").delete_all
    Feature.create!(slug: "performance_logging", category: "Operations", name: "Performance logging", enabled: true)
    Current.reset
    PerformanceLogging::Store.append("event" => "syrus.performance.slow_request", "path" => "/dashboard/jobs")
  end

  it "401s without a token" do
    get "/api/v1/admin/performance"

    expect(response).to have_http_status(:unauthorized)
  end

  it "returns performance diagnostics for admin API clients" do
    get "/api/v1/admin/performance", headers: auth

    expect(response).to have_http_status(:ok)
    body = parse_body
    expect(body["enabled"]).to eq(true)
    expect(body["thresholds"]).to include("slow_request_ms", "slow_sql_ms", "slow_phase_ms")
    expect(body["storage"]).to include("max_events" => PerformanceLogging::Store::MAX_EVENTS)
    expect(body["events"].first).to include("event" => "syrus.performance.slow_request", "path" => "/dashboard/jobs")
  end
end
