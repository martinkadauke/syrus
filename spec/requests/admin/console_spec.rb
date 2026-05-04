require "rails_helper"

RSpec.describe "Admin operator console", type: :request do
  let(:admin) { Factories.user }
  let(:non_admin) { admin; Factories.user }

  describe "GET /admin/console" do
    it "blocks non-admins" do
      sign_in_as(non_admin)
      get "/admin/console"
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to match(/admin/i)
    end

    it "renders the console for admins" do
      sign_in_as(admin)
      get "/admin/console"
      expect(response).to be_successful
      expect(response.body).to include("Operator console")
      expect(response.body).to include("Polling")
      expect(response.body).to include("RunJobs")
      expect(response.body).to include("GitHub HTTP cache")
      expect(response.body).to include("Recent admin actions")
    end
  end

  describe "pause/resume polling" do
    before { sign_in_as(admin) }

    it "pause_polling sets the flag and logs an AdminAction" do
      expect {
        post "/admin/console/pause_polling"
      }.to change { AppSetting.current.tap(&:reload).polling_paused }.from(false).to(true)
        .and change { AdminAction.where(action: "pause_polling").count }.by(1)
      expect(response).to redirect_to(admin_console_path)
    end

    it "unpause_polling clears the flag" do
      AppSetting.current.update!(polling_paused: true)
      expect {
        post "/admin/console/unpause_polling"
      }.to change { AppSetting.current.tap(&:reload).polling_paused }.from(true).to(false)
    end
  end

  describe "pause/resume runs" do
    before { sign_in_as(admin) }

    it "pause_runs sets the flag" do
      expect {
        post "/admin/console/pause_runs"
      }.to change { AppSetting.current.tap(&:reload).runs_paused }.from(false).to(true)
    end

    it "unpause_runs clears the flag" do
      AppSetting.current.update!(runs_paused: true)
      expect {
        post "/admin/console/unpause_runs"
      }.to change { AppSetting.current.tap(&:reload).runs_paused }.from(true).to(false)
    end
  end

  describe "clear_github_cache" do
    before { sign_in_as(admin) }

    it "clears all when no user_id is given" do
      expect(Rails.cache).to receive(:delete_matched).with("github_etag/*").and_return(7)
      post "/admin/console/clear_github_cache"
      expect(response).to redirect_to(admin_console_path)
      expect(flash[:notice]).to match(/Cleared 7 GitHub cache entries for all users/)
      expect(AdminAction.where(action: "clear_github_cache").count).to eq(1)
    end

    it "scopes to a single user when user_id given" do
      target = Factories.user(email_address: "target@example.com")
      expect(Rails.cache).to receive(:delete_matched).with("github_etag/u#{target.id}/*").and_return(2)
      post "/admin/console/clear_github_cache", params: { user_id: target.id }
      expect(flash[:notice]).to include("for target@example.com")
    end

    it "shrugs off cache adapters that don't support delete_matched" do
      allow(Rails.cache).to receive(:delete_matched).and_raise(NotImplementedError)
      post "/admin/console/clear_github_cache"
      expect(response).to redirect_to(admin_console_path)
      expect(flash[:notice]).to match(/Cleared 0 GitHub cache entries/)
    end
  end
end
