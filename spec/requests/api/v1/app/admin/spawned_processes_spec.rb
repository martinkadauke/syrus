require "rails_helper"

RSpec.describe "API: /api/v1/app/admin/processes", type: :request do
  let(:admin) { Factories.user }
  let(:non_admin) do
    admin
    Factories.user
  end

  def parse_body
    JSON.parse(response.body)
  end

  def fixture(**overrides)
    SpawnedProcess.create!({
      kind: "agent",
      command: "claude --print",
      hostname: "syrus-worker-test",
      started_at: 30.seconds.ago,
      last_chunk_at: 5.seconds.ago
    }.merge(overrides))
  end

  it "401s with a JSON error when signed out" do
    get "/api/v1/app/admin/processes"

    expect(response).to have_http_status(:unauthorized)
    expect(parse_body.dig("error", "code")).to eq("unauthorized")
  end

  it "403s with a JSON error for non-admin users" do
    sign_in_as(non_admin)

    get "/api/v1/app/admin/processes"

    expect(response).to have_http_status(:forbidden)
    expect(parse_body.dig("error", "code")).to eq("forbidden")
  end

  it "returns the default active and recent process inventory" do
    sign_in_as(admin)
    running = fixture
    fixture(started_at: 5.hours.ago, finished_at: 4.hours.ago, outcome: "succeeded", exit_status: 0)

    get "/api/v1/app/admin/processes"

    expect(response).to have_http_status(:ok)
    expect(parse_body["processes"].map { |process| process["id"] }).to include(running.id)
    expect(parse_body["running_total"]).to eq(SpawnedProcess.running.count)
  end

  it "filters the process inventory" do
    sign_in_as(admin)
    fixture(kind: "agent")
    grader = fixture(kind: "grader", command: "bin/rspec")

    get "/api/v1/app/admin/processes", params: { kind: "grader", state: "running" }

    expect(response).to have_http_status(:ok)
    expect(parse_body["processes"].map { |process| process["id"] }).to eq([ grader.id ])
  end

  it "returns process detail with host metrics key" do
    sign_in_as(admin)
    process = fixture

    get "/api/v1/app/admin/processes/#{process.id}"

    expect(response).to have_http_status(:ok)
    expect(parse_body).to include(
      "id" => process.id,
      "kind" => "agent",
      "host_metrics" => nil
    )
  end

  it "stamps kill_requested_at" do
    sign_in_as(admin)
    process = fixture

    expect {
      post "/api/v1/app/admin/processes/#{process.id}/kill"
    }.to change { process.reload.kill_requested_at }.from(nil)

    expect(response).to have_http_status(:ok)
    expect(parse_body["kill_requested_at"]).to be_present
    expect(process.kill_requested_by_user).to eq(admin)
  end

  it "returns 409 if the process is already finished" do
    sign_in_as(admin)
    process = fixture(finished_at: Time.current, outcome: "succeeded", exit_status: 0)

    post "/api/v1/app/admin/processes/#{process.id}/kill"

    expect(response).to have_http_status(:conflict)
    expect(parse_body.dig("error", "code")).to eq("already_finished")
  end
end
