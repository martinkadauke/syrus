require "rails_helper"

RSpec.describe PerformanceLogging do
  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(cache_store)
    allow(Rails.logger).to receive(:info)
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

    described_class.record_sql(
      { name: "Job Load", sql: "SELECT *\nFROM jobs\nWHERE title = 'é'" },
      5.25
    )

    event = described_class::Store.recent.first
    expect(event).to include(
      "event" => "syrus.performance.slow_sql",
      "duration_ms" => 5.3,
      "name" => "Job Load",
      "sql" => "SELECT * FROM jobs WHERE title = 'é'"
    )
    expect(event["sql"].encoding).to eq(Encoding::UTF_8)
    expect(Rails.logger).to have_received(:info).with(/syrus\.performance\.slow_sql/)
  end

  it "records slow request events with SQL counters" do
    Feature.create!(slug: "performance_logging", category: "Operations", name: "Performance logging", enabled: true)
    Current.reset
    allow(described_class).to receive(:slow_request_threshold_ms).and_return(1.0)
    Current.performance_sql_count = 3
    Current.performance_sql_duration_ms = 42.25
    Current.performance_slow_sql_count = 1

    described_class.record_request(
      {
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
      "duration_ms" => 1_500.3,
      "path" => "/dashboard/jobs?view=list",
      "sql_count" => 3,
      "sql_duration_ms" => 42.3,
      "slow_sql_count" => 1
    )
  end

  it "records slow phase events with safe metadata" do
    Feature.create!(slug: "performance_logging", category: "Operations", name: "Performance logging", enabled: true)
    Current.reset
    allow(described_class).to receive(:slow_phase_threshold_ms).and_return(0.0)

    described_class.phase("dashboard_payload", subject: "job", view: "list") { "done" }

    event = described_class::Store.recent.first
    expect(event).to include(
      "event" => "syrus.performance.slow_phase",
      "phase" => "dashboard_payload",
      "metadata" => { "subject" => "job", "view" => "list" }
    )
  end
end
