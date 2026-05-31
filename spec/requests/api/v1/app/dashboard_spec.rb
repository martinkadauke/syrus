require "rails_helper"

RSpec.describe "App API dashboard commands", type: :request do
  let(:user) { Factories.user }
  let(:repo) { Factories.repository(user: user, owner: "acme", name: "widgets") }

  before { sign_in_as(user) }

  def parse_body = JSON.parse(response.body)

  def finish_initial_work(job, provider: "claude")
    job.initial_run.update!(
      state: "succeeded",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago,
      agent_provider: provider
    )
    job.latest_workflow.update!(state: "succeeded", started_at: 2.minutes.ago, finished_at: 1.minute.ago)
  end

  describe "PATCH /api/v1/app/dashboard/preferences" do
    it "updates dashboard sort, visible columns, and Kanban lanes" do
      patch "/api/v1/app/dashboard/preferences",
            params: {
              subject: "jobs",
              sort_column: "started_at",
              sort_direction: "asc",
              visible_columns: %w[state repository],
              kanban_lanes: %w[queued running]
            },
            as: :json

      expect(response).to have_http_status(:ok)
      expect(parse_body["message"]).to eq("Dashboard preferences updated.")
      preferences = user.reload.dashboard_preferences.fetch("jobs")
      expect(preferences).to include(
        "sort_column" => "started_at",
        "sort_direction" => "asc",
        "visible_columns" => %w[title state repository],
        "kanban_lanes" => %w[queued running]
      )
    end

    it "returns structured validation errors" do
      patch "/api/v1/app/dashboard/preferences",
            params: { subject: "jobs", sort_column: "vapor", sort_direction: "asc" },
            as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(parse_body).to eq(
        "error" => {
          "code" => "validation_failed",
          "message" => "Unknown dashboard sort column: vapor"
        }
      )
    end
  end

  describe "POST /api/v1/app/dashboard/landing_pause" do
    it "pauses landing" do
      expect {
        post "/api/v1/app/dashboard/landing_pause", as: :json
      }.not_to have_enqueued_job(LandingQueueProcessorJob)

      expect(response).to have_http_status(:ok)
      expect(user.reload.landing_paused).to eq(true)
      expect(parse_body).to include("message" => "Landing paused.", "landing_paused" => true)
    end

    it "resumes landing and kicks the processor" do
      user.update!(landing_paused: true)

      expect {
        post "/api/v1/app/dashboard/landing_pause", as: :json
      }.to have_enqueued_job(LandingQueueProcessorJob)

      expect(response).to have_http_status(:ok)
      expect(user.reload.landing_paused).to eq(false)
      expect(parse_body).to include("message" => "Landing resumed.", "landing_paused" => false)
    end
  end

  describe "POST /api/v1/app/dashboard/jobs/bulk" do
    it "requires selected jobs" do
      post "/api/v1/app/dashboard/jobs/bulk", params: { bulk_action: "close" }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(parse_body.dig("error", "message")).to eq("Select at least one job.")
    end

    it "retries eligible jobs" do
      first = Factories.job(repository: repo, issue_number: 1, agent_provider: "claude")
      second = Factories.job(repository: repo, issue_number: 2, agent_provider: "codex")
      finish_initial_work(first, provider: "claude")
      finish_initial_work(second, provider: "codex")

      expect(AppEvents).to receive(:broadcast).with(
        user: user,
        type: "updated",
        resource: "job",
        id: nil,
        changed: [ "bulk" ],
        payload: { "action" => "retry", "affected_job_ids" => contain_exactly(first.id, second.id) }
      )

      expect {
        post "/api/v1/app/dashboard/jobs/bulk",
             params: { job_ids: [ first.id, second.id ], bulk_action: "retry" },
             as: :json
      }.to change { Workflow.where(trigger_kind: "retry").count }.by(2)

      expect(response).to have_http_status(:ok)
      expect(parse_body["message"]).to eq("Retry enqueued for 2 jobs.")
      expect(parse_body["affected_job_ids"]).to contain_exactly(first.id, second.id)
    end

    it "closes selected open jobs without mutating another user's job" do
      mine = Factories.job(repository: repo, issue_number: 1)
      other_user = Factories.user
      other_repo = Factories.repository(user: other_user, owner: "globex", name: "private")
      theirs = Factories.job(repository: other_repo, issue_number: 2)
      allow(AppEvents).to receive(:broadcast)

      post "/api/v1/app/dashboard/jobs/bulk",
           params: { job_ids: [ mine.id, theirs.id ], bulk_action: "close" },
           as: :json

      expect(response).to have_http_status(:ok)
      expect(mine.reload).to be_closed
      expect(theirs.reload).to be_open
      expect(parse_body["affected_job_ids"]).to eq([ mine.id ])
    end

    it "approves selected implemented jobs and reports auto-merge skips" do
      repo.update!(auto_merge_enabled: true)
      disabled_repo = Factories.repository(user: user, owner: "acme", name: "lib", auto_merge_enabled: false)
      enabled = Factories.job(repository: repo, issue_number: 10)
      disabled = Factories.job(repository: disabled_repo, issue_number: 11)
      enabled.update!(state: "implemented")
      disabled.update!(state: "implemented")
      allow(AppEvents).to receive(:broadcast)

      post "/api/v1/app/dashboard/jobs/bulk",
           params: { job_ids: [ enabled.id, disabled.id ], bulk_action: "approve" },
           as: :json

      expect(response).to have_http_status(:ok)
      expect(enabled.reload).to be_approved
      expect(disabled.reload).to be_implemented
      expect(parse_body["message"]).to include("Approved 1 job in batch")
      expect(parse_body["message"]).to include("Skipped 1 job whose repository has auto-merge disabled (acme/lib)")
      expect(parse_body["skipped_job_ids"]).to eq([ disabled.id ])
      expect(parse_body["batch_id"]).to be_present
    end

    it "returns review payloads for selected implemented jobs" do
      first = Factories.job(repository: repo, issue_number: 1, issue_title: "Review the aqueduct")
      second = Factories.job(repository: repo, issue_number: 2, issue_title: "Review the forum")
      first.update!(state: "implemented")
      second.update!(state: "implemented")
      first.initial_run.update!(agent_diff: "diff --git a/a.txt b/a.txt\n+first")
      second.initial_run.update!(agent_diff: "diff --git a/b.txt b/b.txt\n+second")

      post "/api/v1/app/dashboard/jobs/bulk",
           params: { job_ids: [ first.id, second.id ], bulk_action: "review_approve" },
           as: :json

      expect(response).to have_http_status(:ok)
      expect(parse_body["review_jobs"].map { |job| job["id"] }).to contain_exactly(first.id, second.id)
      expect(parse_body["review_jobs"].map { |job| job["diff"] }.join("\n")).to include("+first", "+second")
    end

    it "commits reviewed approvals and skips rejected choices" do
      approved = Factories.job(repository: repo, issue_number: 1)
      skipped = Factories.job(repository: repo, issue_number: 2)
      approved.update!(state: "implemented")
      skipped.update!(state: "implemented")
      allow(AppEvents).to receive(:broadcast)

      post "/api/v1/app/dashboard/jobs/bulk",
           params: {
             job_ids: [ approved.id, skipped.id ],
             bulk_action: "commit_review_approval",
             approval_choices: {
               approved.id.to_s => "approve",
               skipped.id.to_s => "skip"
             }
           },
           as: :json

      expect(response).to have_http_status(:ok)
      expect(approved.reload).to be_approved
      expect(skipped.reload).to be_implemented
      expect(parse_body["affected_job_ids"]).to eq([ approved.id ])
    end

    it "applies an existing tag to selected jobs" do
      first = Factories.job(repository: repo, issue_number: 1)
      second = Factories.job(repository: repo, issue_number: 2)
      tag = Factories.tag(user: user, name: "epic:tags", color: "indigo")
      allow(AppEvents).to receive(:broadcast)

      post "/api/v1/app/dashboard/jobs/bulk",
           params: { job_ids: [ first.id, second.id ], bulk_action: "apply_tag", tag_id: tag.id },
           as: :json

      expect(response).to have_http_status(:ok)
      expect(first.reload.tags).to contain_exactly(tag)
      expect(second.reload.tags).to contain_exactly(tag)
      expect(parse_body["message"]).to eq("Applied epic:tags to 2 jobs.")
      expect(parse_body.dig("tag", "name")).to eq("epic:tags")
    end
  end

  describe "PATCH /api/v1/app/dashboard/epics/:id/auto_approval" do
    it "updates one of the current user's Epics" do
      epic = Factories.epic(user: user, repository: repo, state: "ready", title: "Polish aqueduct")

      patch "/api/v1/app/dashboard/epics/#{epic.id}/auto_approval",
            params: { epic: { auto_approve_mode: "if_graders_pass" } },
            as: :json

      expect(response).to have_http_status(:ok)
      expect(epic.reload.auto_approve_mode).to eq("if_graders_pass")
      expect(parse_body).to include(
        "message" => "Epic auto-approval updated.",
        "epic" => include("id" => epic.id, "auto_approve_mode" => "if_graders_pass")
      )
    end

    it "does not expose another user's Epic" do
      other_user = Factories.user
      other_repo = Factories.repository(user: other_user, owner: "globex", name: "private")
      other_epic = Factories.epic(user: other_user, repository: other_repo)

      patch "/api/v1/app/dashboard/epics/#{other_epic.id}/auto_approval",
            params: { epic: { auto_approve_mode: "if_graders_pass" } },
            as: :json

      expect(response).to have_http_status(:not_found)
      expect(other_epic.reload.auto_approve_mode).to eq("never")
    end
  end
end
