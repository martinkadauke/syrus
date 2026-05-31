require "rails_helper"

RSpec.describe "App API dashboard commands", type: :request do
  let(:user) { Factories.user }
  let(:repo) { Factories.repository(user: user, owner: "acme", name: "widgets") }

  before { sign_in_as(user) }

  def parse_body = JSON.parse(response.body)

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
