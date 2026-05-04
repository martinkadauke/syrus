require "rails_helper"

RSpec.describe "Admin stuck list", type: :request do
  let(:admin) { Factories.user }
  let(:non_admin) do
    admin
    Factories.user
  end

  describe "GET /admin/stuck" do
    it "blocks non-admins" do
      sign_in_as(non_admin)
      get "/admin/stuck"
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to match(/admin/i)
    end

    it "renders the empty state when nothing is stuck" do
      sign_in_as(admin)
      get "/admin/stuck"
      expect(response).to be_successful
      expect(response.body).to include("Nothing stuck")
    end

    it "lists a stuck Run with severity, kind, detail, and a link to its job" do
      sign_in_as(admin)
      job = Factories.job(user: admin)
      run = job.initial_run
      run.update_columns(state: "running",
                         started_at: 10.minutes.ago,
                         last_heartbeat_at: 10.minutes.ago)

      get "/admin/stuck"
      expect(response).to be_successful
      expect(response.body).to include("stale_heartbeat")
      expect(response.body).to include("warn")
      expect(response.body).to include("Run ##{run.id}")
      expect(response.body).to include("href=\"#{job_path(job)}\"")
    end

    it "promotes Runs past the reaper threshold to alarm-level reaper_starved" do
      sign_in_as(admin)
      job = Factories.job(user: admin)
      run = job.initial_run
      run.update_columns(state: "running",
                         started_at: (Run::STALE_HEARTBEAT_THRESHOLD + 5.minutes).ago,
                         last_heartbeat_at: (Run::STALE_HEARTBEAT_THRESHOLD + 5.minutes).ago)

      get "/admin/stuck"
      expect(response.body).to include("reaper_starved")
      expect(response.body).to include("alarm")
    end

    it "wires the auto-refresh Stimulus controller" do
      sign_in_as(admin)
      get "/admin/stuck"
      expect(response.body).to include('data-controller="auto-refresh"')
    end
  end
end
