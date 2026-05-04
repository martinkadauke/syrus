require "rails_helper"

RSpec.describe "Admin overview", type: :request do
  let(:admin) { Factories.user }
  let(:non_admin) do
    admin
    Factories.user
  end

  describe "GET /admin" do
    it "redirects unauthenticated users" do
      get "/admin"
      expect(response).to redirect_to(new_session_path).or redirect_to(new_user_path)
    end

    it "blocks non-admins" do
      sign_in_as(non_admin)
      get "/admin"
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to match(/admin/i)
    end

    it "renders the overview for admins" do
      sign_in_as(admin)
      get "/admin"
      expect(response).to be_successful
      expect(response.body).to include("Admin overview")
      expect(response.body).to include("Active runs")
      expect(response.body).to include("Workers")
      expect(response.body).to include("Claude session capture")
      expect(response.body).to include("Stuck things")
    end

    it "wires the auto-refresh Stimulus controller" do
      sign_in_as(admin)
      get "/admin"
      expect(response.body).to include('data-controller="auto-refresh"')
      expect(response.body).to include('data-auto-refresh-interval-value="30"')
    end

    it "links each tile to its drill-down page" do
      sign_in_as(admin)
      get "/admin"
      expect(response.body).to include('href="/admin/queue/active"')
      expect(response.body).to include('href="/admin/queue/pending"')
      expect(response.body).to include('href="/admin/queue/workers"')
      expect(response.body).to include('href="/admin/queue/recurring"')
      expect(response.body).to include('href="/admin/queue/failed"')
    end

    it "surfaces stuck-Run heartbeats in the watchlist" do
      sign_in_as(admin)
      job = Factories.job(user: admin)
      run = job.initial_run
      run.update_columns(state: "running",
                         started_at: 1.hour.ago,
                         last_heartbeat_at: 1.hour.ago)

      get "/admin"
      expect(response.body).to include("stale_heartbeat")
      expect(response.body).to include("Run ##{run.id}")
    end
  end
end
