require "rails_helper"

RSpec.describe "API: /api/v1/admin/operational_logs", type: :request do
  let!(:admin) { Factories.user(admin: true) }
  let!(:non_admin) { Factories.user(admin: false) }
  let!(:repository) { Factories.repository(user: admin, owner: "tkadauke", name: "syrus") }
  let(:admin_token) { admin.generate_api_token! }
  let(:non_admin_token) { non_admin.generate_api_token! }

  def auth(token = admin_token) = { "Authorization" => "Bearer #{token}" }
  def parse_body = JSON.parse(response.body)

  before do
    Feature.where(slug: "operational_log_indexing").delete_all
    Feature.create!(slug: "operational_log_indexing", category: "Operations", name: "Operational log indexing", enabled: true)
    Feature.clear_enabled_cache!("operational_log_indexing")
    PluginRecord.find_by!(name: "syrus_dev").update!(enabled: true)
    allow(SyrusVersion).to receive(:current).and_return("current-sha")
    allow(OperationalLogging).to receive(:enabled_for_instance?).and_return(true)
    Current.reset
    prepare_search_tables
  end

  after { Current.reset }

  it "401s without a token" do
    get "/api/v1/admin/operational_logs"

    expect(response).to have_http_status(:unauthorized)
  end

  it "403s for non-admin API tokens" do
    get "/api/v1/admin/operational_logs", headers: auth(non_admin_token)

    expect(response).to have_http_status(:forbidden)
  end

  it "returns indexed operational logs for admin API clients" do
    job = Factories.job(repository: repository, user: admin)
    run = job.initial_run
    matching = OperationalLogEvent.create!(
      occurred_at: Time.current,
      level: "error",
      role: "worker",
      hostname: "worker-a",
      app_revision: "current-sha",
      source: "active_job",
      job_id: job.id,
      workflow_id: job.workflows.first.id,
      run_id: run.id,
      message: "preview failed token=super-secret",
      context: { "api_key" => "api_key=raw-secret" }
    )
    OperationalLogIndex.upsert(matching)

    get "/api/v1/admin/operational_logs",
        params: { query: "preview", level: "error", role: "worker", since: "1h", revision_scope: "all" },
        headers: auth

    expect(response).to have_http_status(:ok)
    body = parse_body
    expect(body["enabled"]).to eq(true)
    expect(body["logs"].size).to eq(1)
    expect(body.dig("logs", 0)).to include(
      "id" => matching.id,
      "level" => "error",
      "role" => "worker",
      "job_id" => job.id,
      "run_id" => run.id
    )
    expect(body.to_json).not_to include("super-secret", "raw-secret")
    expect(body.dig("logs", 0, "message")).to include("token=[REDACTED]")
    expect(body.dig("logs", 0, "context")).to include("api_key" => "api_key=[REDACTED]")
  end

  it "404s when the Syrus Dev plugin is disabled" do
    PluginRecord.find_by!(name: "syrus_dev").update!(enabled: false)

    get "/api/v1/admin/operational_logs", headers: auth

    expect(response).to have_http_status(:not_found)
    expect(parse_body).to include("error" => "syrus_dev_plugin_disabled")
  end

  def prepare_search_tables
    SearchRecord.connection.execute("DROP TABLE IF EXISTS operational_log_fts")
    SearchRecord.connection.execute(<<~SQL)
      CREATE VIRTUAL TABLE operational_log_fts
      USING fts5(
        message,
        context_text,
        context_json UNINDEXED,
        operational_log_event_id UNINDEXED,
        occurred_at UNINDEXED,
        level UNINDEXED,
        role UNINDEXED,
        hostname UNINDEXED,
        app_revision UNINDEXED,
        pid UNINDEXED,
        source UNINDEXED,
        job_id UNINDEXED,
        workflow_id UNINDEXED,
        run_id UNINDEXED,
        request_id UNINDEXED,
        tokenize = 'porter unicode61'
      )
    SQL
  end
end
