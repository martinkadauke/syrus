require "rails_helper"

RSpec.describe PerformanceLogging do
  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(cache_store)
    allow(Rails.logger).to receive(:info)
    allow(SyrusVersion).to receive(:current).and_return("sha-current")
    Feature.where(slug: "performance_logging").delete_all
    Current.reset
  end

  after do
    Current.reset
  end

  it "stays disabled unless the feature gate is enabled" do
    Feature.create!(slug: "performance_logging", category: "Operations", name: "Performance logging", enabled: false)
    Current.reset

    described_class.record_sql({ name: "Job Load", sql: "SELECT * FROM jobs" }, 500)

    expect(described_class::Store.recent).to be_empty
    expect(Rails.logger).not_to have_received(:info)
  end

  it "records slow SQL events to logs and the recent-event buffer" do
    Feature.create!(slug: "performance_logging", category: "Operations", name: "Performance logging", enabled: true)
    Current.reset
    allow(described_class).to receive(:slow_sql_threshold_ms).and_return(1.0)

    described_class.with_request_context(request_id: "req-123", method: "GET", path: "/jobs", user_id: 7, admin: true) do
      described_class.record_sql(
        { name: "Job Load", sql: "SELECT *\nFROM jobs\nWHERE title = 'é' AND id = 42" },
        5.25
      )
    end

    event = described_class::Store.recent.first
    expect(event).to include(
      "event" => "syrus.performance.slow_sql",
      "app_revision" => "sha-current",
      "request_id" => "req-123",
      "path" => "/jobs",
      "user_id" => 7,
      "admin" => true,
      "duration_ms" => 5.3,
      "name" => "Job Load",
      "sql" => "SELECT * FROM jobs WHERE title = 'é' AND id = 42",
      "fingerprint" => "SELECT * FROM jobs WHERE title = ? AND id = ?"
    )
    expect(event["sql"].encoding).to eq(Encoding::UTF_8)
    expect(Rails.logger).to have_received(:info).with(/syrus\.performance\.slow_sql/)
  end

  it "records slow request events with SQL counters and top SQL fingerprints" do
    Feature.create!(slug: "performance_logging", category: "Operations", name: "Performance logging", enabled: true)
    Current.reset
    allow(described_class).to receive(:slow_request_threshold_ms).and_return(1.0)
    allow(described_class).to receive(:slow_sql_threshold_ms).and_return(1_000.0)

    described_class.with_request_context(request_id: "req-abc", path: "/dashboard/jobs?view=list", user_id: 9) do
      described_class.record_sql({ name: "Job Load", sql: "SELECT * FROM jobs WHERE id = 1" }, 20.0)
      described_class.record_sql({ name: "Job Load", sql: "SELECT * FROM jobs WHERE id = 2" }, 22.25)
      described_class.record_sql({ name: "Run Count", sql: "SELECT COUNT(*) FROM runs" }, 8.0)
    end

    described_class.record_request(
      {
        request_id: "req-abc",
        method: "GET",
        path: "/dashboard/jobs?view=list",
        controller: "Api::V1::App::DashboardController",
        action: "show",
        format: "json",
        status: 200,
        view_runtime: 1.2,
        db_runtime: 42.25
      },
      1_500.25
    )

    event = described_class::Store.recent.first
    expect(event).to include(
      "event" => "syrus.performance.slow_request",
      "request_id" => "req-abc",
      "duration_ms" => 1_500.3,
      "path" => "/dashboard/jobs?view=list",
      "sql_count" => 3,
      "sql_duration_ms" => 50.3,
      "slow_sql_count" => 0
    )
    expect(event["top_sql_fingerprints"].first).to include(
      "fingerprint" => "SELECT * FROM jobs WHERE id = ?",
      "count" => 2,
      "total_duration_ms" => 42.3,
      "max_duration_ms" => 22.3
    )
  end

  it "records slow phase events with safe metadata" do
    Feature.create!(slug: "performance_logging", category: "Operations", name: "Performance logging", enabled: true)
    Current.reset
    allow(described_class).to receive(:slow_phase_threshold_ms).and_return(0.0)

    described_class.with_request_context(request_id: "req-phase", path: "/dashboard") do
      described_class.phase("dashboard_payload", subject: "job", view: "list") { "done" }
    end

    event = described_class::Store.recent.first
    expect(event).to include(
      "event" => "syrus.performance.slow_phase",
      "request_id" => "req-phase",
      "path" => "/dashboard",
      "phase" => "dashboard_payload",
      "metadata" => { "subject" => "job", "view" => "list" }
    )
  end
end
