require "rails_helper"

RSpec.describe "API: /api/v1/app/admin/performance", type: :request do
  let!(:admin) { Factories.user(admin: true) }
  let(:non_admin) { Factories.user(admin: false) }
  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

  def parse_body = JSON.parse(response.body)

  before do
    allow(Rails).to receive(:cache).and_return(cache_store)
    PerformanceLogging::Store.clear!
    allow(SyrusVersion).to receive(:current).and_return("new-sha")
    Feature.where(slug: "performance_logging").delete_all
    Feature.create!(slug: "performance_logging", category: "Operations", name: "Performance logging", enabled: true)
    PluginRecord.find_by!(name: "syrus_dev").update!(enabled: true)
    Current.reset
    PerformanceLogging::Store.clear!
    PerformanceLogging::Store.append(
      "event" => "syrus.performance.slow_phase",
      "phase" => "dashboard_payload",
      "duration_ms" => 700.0,
      "metadata" => { "view" => "jobs" },
      "occurred_at" => "2026-08-01T12:00:00Z",
      "app_revision" => "new-sha"
    )
    PerformanceLogging::Store.append(
      "event" => "syrus.performance.slow_phase",
      "phase" => "stale_dashboard_payload",
      "duration_ms" => 900.0,
      "metadata" => { "view" => "jobs" },
      "occurred_at" => "2026-08-01T11:00:00Z",
      "app_revision" => "old-sha"
    )
    PerformanceLogging::Store.append(
      "event" => PerformanceLogging::BROWSER_TRACE_EVENT,
      "name" => "dashboard.route",
      "path" => "/dashboard/jobs?smart_folder_id=7",
      "duration_ms" => 1500.0,
      "metadata" => { "subject" => "job", "rows_count" => "0" },
      "api_requests" => [
        { "name" => "dashboard.rows", "request_id" => "rows-request", "duration_ms" => 1200.0, "status" => 200 }
      ],
      "occurred_at" => "2026-08-01T12:00:01Z",
      "app_revision" => "new-sha"
    )
  end

  after do
    PerformanceLogging::Store.clear!
    Current.reset
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
    expect(body["current_revision"]).to eq("new-sha")
    expect(body["revision_scope"]).to eq("current")
    expect(body["events"]).to include(include("event" => "syrus.performance.slow_phase", "phase" => "dashboard_payload"))
    expect(body["events"].to_s).not_to include("stale_dashboard_payload")
    expect(body.dig("summaries", "slow_phases").first).to include(
      "phase" => "dashboard_payload",
      "count" => 1,
      "max_duration_ms" => 700.0,
      "recent_metadata" => { "view" => "jobs" }
    )
    expect(body.dig("summaries", "browser_traces").first).to include(
      "name" => "dashboard.route",
      "path" => "/dashboard/jobs?smart_folder_id=7",
      "count" => 1,
      "max_duration_ms" => 1500.0,
      "max_api_duration_ms" => 1200.0,
      "recent_api_request_ids" => [ "rows-request" ],
      "recent_metadata" => { "subject" => "job", "rows_count" => "0" }
    )
  end

  it "can include events from all app revisions" do
    sign_in_as(admin)

    get "/api/v1/app/admin/performance", params: { revision_scope: "all" }

    expect(response).to have_http_status(:ok)
    expect(parse_body["events"].map { |event| event["app_revision"] }).to contain_exactly("new-sha", "new-sha", "old-sha")
  end

  it "404s when the Syrus Dev plugin is disabled" do
    PluginRecord.find_by!(name: "syrus_dev").update!(enabled: false)
    sign_in_as(admin)

    get "/api/v1/app/admin/performance"

    expect(response).to have_http_status(:not_found)
    expect(parse_body).to include("error" => "syrus_dev_plugin_disabled")
  end
end
