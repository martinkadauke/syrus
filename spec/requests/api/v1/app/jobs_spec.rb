require "rails_helper"

RSpec.describe "App API job detail", type: :request do
  let(:user) { Factories.user }
  let(:repo) { Factories.repository(user: user, owner: "acme", name: "widgets", default_branch: "main") }
  let(:job) do
    Factories.job(
      repository: repo,
      issue_number: 42,
      issue_title: "Repair aqueduct",
      issue_body: "Water should go uphill, apparently.",
      branch_name: "syrus/issue-42",
      pr_number: 7,
      pr_mergeable: true,
      pr_mergeable_checked_at: Time.current
    )
  end

  before { sign_in_as(user) }

  def parse_body = JSON.parse(response.body)

  it "returns a structured job detail payload for React rendering" do
    user.update!(admin: false)
    tag = Factories.tag(user: user, name: "priority:forum")
    job.job_tags.create!(tag: tag)
    target = Factories.job(repository: repo, issue_number: 41, issue_title: "Build hill")
    dependency = job.dependencies.create!(depends_on_job: target, source: "manual", created_by_user: user)
    attachment = job.job_attachments.create!(
      user: user,
      kind: "google_doc",
      title: "Roman hydraulics",
      google_doc_url: "https://docs.google.com/document/d/aqueduct/edit"
    )
    run = job.initial_run
    run.start!
    run.save!
    run.job_logs.create!(sequence: 0, kind: "stdout", chunk: "digging trench")
    run.run_health_snapshots.create!(run_state: "running", health_status: "healthy", log_count: 1)
    run.create_run_diagnostic!(error_class: "Timeout::Error", error_message: "too much marble")

    get "/api/v1/app/jobs/#{job.id}"

    expect(response).to have_http_status(:ok)
    body = parse_body
    expect(body.dig("job", "id")).to eq(job.id)
    expect(body.dig("job", "issue_title")).to eq("Repair aqueduct")
    expect(body.dig("job", "pr_url")).to eq("https://github.com/acme/widgets/pull/7")
    expect(body.dig("repository", "slug")).to eq("acme/widgets")
    expect(body["pinned"]).to eq(false)
    expect(body["tags"]).to contain_exactly(include("id" => tag.id, "name" => "priority:forum"))
    expect(body["dependencies"]).to contain_exactly(include(
      "id" => dependency.id,
      "manual" => true,
      "depends_on_job" => include("id" => target.id, "repository_slug" => "acme/widgets")
    ))
    expect(body["attachments"]).to contain_exactly(include(
      "id" => attachment.id,
      "title" => "Roman hydraulics",
      "google_doc_url" => "https://docs.google.com/document/d/aqueduct/edit",
      "app_delete_path" => "/api/v1/app/jobs/#{job.id}/attachments/#{attachment.id}"
    ))
    expect(body.dig("actions", "can_poll_feedback")).to eq(true)
    expect(body.dig("actions", "can_check_mergeability")).to eq(true)
    expect(body.dig("paths", "app_poll_feedback_path")).to eq("/api/v1/app/jobs/#{job.id}/poll_feedback")
    expect(body.dig("paths", "app_timeline_path")).to eq("/api/v1/app/jobs/#{job.id}/timeline")

    workflow = body["workflows"].first
    expect(workflow).to include("trigger_kind" => "initial")
    expect(workflow["app_retry_step_path"]).to eq("/api/v1/app/jobs/#{job.id}/workflows/#{workflow['id']}/retry_step")
    first_run = workflow["steps"].flat_map { |step| step["runs"] }.find { |payload| payload["id"] == run.id }
    expect(first_run).to include(
      "state" => "running",
      "job_log_count" => 1,
      "can_stop" => true,
      "can_diagnose" => true,
      "app_stop_path" => "/api/v1/app/jobs/#{job.id}/runs/#{run.id}/stop"
    )
    expect(first_run["health_snapshots"]).to contain_exactly(include("health_status" => "healthy", "run_state" => "running"))
    expect(first_run["run_diagnostic"]).to include("present" => true)
    expect(first_run["run_diagnostic"]).not_to have_key("error_message")
  end

  it "returns admin-only diagnostic detail to admins" do
    user.update!(admin: true)
    run = job.initial_run
    diagnostic = run.create_run_diagnostic!(
      error_class: "RuntimeError",
      error_message: "broken chisel",
      error_backtrace: "app/work.rb:1",
      repo_snapshot: { "slug" => repo.slug }
    )

    get "/api/v1/app/jobs/#{job.id}"

    first_run = parse_body["workflows"].flat_map { |workflow| workflow["steps"] }.flat_map { |step| step["runs"] }.find { |payload| payload["id"] == run.id }
    expect(first_run["run_diagnostic"]).to include(
      "id" => diagnostic.id,
      "error_class" => "RuntimeError",
      "error_message" => "broken chisel",
      "error_backtrace" => "app/work.rb:1",
      "repo_snapshot" => { "slug" => "acme/widgets" }
    )
  end

  it "returns a timeline payload separately from the detail payload" do
    run = job.initial_run
    run.start!
    run.fail!
    run.save!

    get "/api/v1/app/jobs/#{job.id}/timeline"

    expect(response).to have_http_status(:ok)
    body = parse_body
    expect(body["job_id"]).to eq(job.id)
    expect(body["events"]).to include(
      include("source" => "workflow", "title" => include("created")),
      include("source" => "run", "title" => "Run ##{run.id} failed")
    )
    expect(body["events"].first).to include("at", "kind", "source", "title", "ref")
  end

  it "does not expose another user's job" do
    other_user = Factories.user
    other_repo = Factories.repository(user: other_user, owner: "globex", name: "private")
    other_job = Factories.job(repository: other_repo, issue_number: 99)

    get "/api/v1/app/jobs/#{other_job.id}"

    expect(response).to have_http_status(:not_found)
  end
end
