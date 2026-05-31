require "rails_helper"

RSpec.describe "App API job pins", type: :request do
  let(:user) { Factories.user }
  let(:repo) { Factories.repository(user: user, owner: "acme", name: "widgets") }
  let(:job) { Factories.job_record(repository: repo, issue_number: 42) }

  before { sign_in_as(user) }

  def parse_body = JSON.parse(response.body)
  def app_pin_path(job_record) = "/api/v1/app/jobs/#{job_record.id}/pin"

  it "pins one of the current user's jobs" do
    expect(AppEvents).to receive(:broadcast).with(
      user: user,
      type: "updated",
      resource: "job",
      id: job.id,
      changed: [ "pin" ],
      payload: { "pinned" => true }
    )

    expect {
      post app_pin_path(job), as: :json
    }.to change { user.job_pins.where(job: job).count }.by(1)

    expect(response).to have_http_status(:ok)
    expect(parse_body).to include(
      "message" => "Job pinned.",
      "job" => include("id" => job.id, "pinned" => true, "job_path" => job_path(job)),
      "paths" => include("app_pin_path" => app_pin_path(job), "job_path" => job_path(job))
    )
  end

  it "does not duplicate an existing pin" do
    Factories.job_pin(user: user, job: job)
    allow(AppEvents).to receive(:broadcast)

    expect {
      post app_pin_path(job), as: :json
    }.not_to change { user.job_pins.where(job: job).count }

    expect(response).to have_http_status(:ok)
    expect(parse_body.dig("job", "pinned")).to eq(true)
  end

  it "unpins one of the current user's jobs" do
    Factories.job_pin(user: user, job: job)
    expect(AppEvents).to receive(:broadcast).with(
      user: user,
      type: "updated",
      resource: "job",
      id: job.id,
      changed: [ "pin" ],
      payload: { "pinned" => false }
    )

    expect {
      delete app_pin_path(job), as: :json
    }.to change { user.job_pins.where(job: job).count }.by(-1)

    expect(response).to have_http_status(:ok)
    expect(parse_body).to include(
      "message" => "Job unpinned.",
      "job" => include("id" => job.id, "pinned" => false)
    )
  end

  it "does not expose another user's job" do
    other_user = Factories.user
    other_repo = Factories.repository(user: other_user, owner: "globex", name: "private")
    other_job = Factories.job_record(repository: other_repo, issue_number: 99)

    post app_pin_path(other_job), as: :json

    expect(response).to have_http_status(:not_found)
    expect(user.job_pins.where(job: other_job)).to be_empty
    expect(other_user.job_pins.where(job: other_job)).to be_empty
  end
end
