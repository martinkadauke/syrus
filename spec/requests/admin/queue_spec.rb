require "rails_helper"

# Note: SolidQueue's tables aren't loaded in the dev/test
# single-database setup, so the controller's rescue path
# (`@queue_unreachable`) gets exercised here. Production-shape
# behavior (with the queue DB present) is tested by hand via the
# admin UI on staging.
RSpec.describe "Admin queue inspector", type: :request do
  let(:admin) { Factories.user }
  let(:non_admin) do
    admin
    Factories.user
  end

  describe "GET /admin/queue" do
    it "redirects unauthenticated users" do
      get "/admin/queue"
      expect(response).to redirect_to(new_session_path).or redirect_to(new_user_path)
    end

    it "blocks non-admins" do
      sign_in_as(non_admin)
      get "/admin/queue"
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to match(/admin/i)
    end

    it "redirects /admin/queue to /admin/queue/active" do
      sign_in_as(admin)
      get "/admin/queue"
      expect(response).to redirect_to("/admin/queue/active")
    end
  end

  describe "GET /admin/queue/:tab" do
    before { sign_in_as(admin) }

    %w[active pending failed recurring workers].each do |tab|
      it "renders the #{tab} tab successfully (whether SQ tables are reachable or not)" do
        get "/admin/queue/#{tab}"
        expect(response).to be_successful
        expect(response.body).to include("SolidQueue inspector")
      end
    end

    it "ignores an unknown tab — route constraint returns 404" do
      get "/admin/queue/bogus"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /admin/queue/reap_stale_runs" do
    it "blocks non-admins" do
      sign_in_as(non_admin)
      post "/admin/queue/reap_stale_runs"
      expect(response).to redirect_to(root_path)
    end

    it "runs ReapStaleRunsJob inline and redirects" do
      sign_in_as(admin)
      expect(ReapStaleRunsJob).to receive(:perform_now)
      post "/admin/queue/reap_stale_runs"
      expect(response).to redirect_to("/admin/queue/active")
      expect(flash[:notice]).to match(/Reap/)
    end
  end
end
