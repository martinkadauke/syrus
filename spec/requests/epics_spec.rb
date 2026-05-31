require "rails_helper"
require "cgi"

RSpec.describe "Epics", type: :request do
  let(:user) { Factories.user }
  let(:repo) { Factories.repository(user: user, owner: "acme", name: "widgets") }

  describe "GET /epics" do
    it "redirects to the canonical Epic dashboard route" do
      get epics_path

      expect(response).to have_http_status(:found)
      expect(response).to redirect_to("/dashboard/epics")
    end

    it "preserves query params in the compatibility redirect" do
      q = Filters::QueryParam.encode("and" => [ { "field" => "state", "op" => "is", "value" => "ready" } ])

      get epics_path, params: { q: q, smart_folder_id: "12", subject: "job" }

      expect(response).to have_http_status(:found)
      expect(response.location).to eq("http://www.example.com/dashboard/epics?q=#{CGI.escape(q)}&smart_folder_id=12")
    end
  end

  describe "PATCH /epics/:id/archive" do
    it "archives an active Epic and redirects to the Epic dashboard" do
      sign_in_as(user)
      epic = Factories.epic(user: user, repository: repo, state: "ready")

      patch archive_epic_path(epic)

      expect(response).to redirect_to(epics_path)
      expect(flash[:notice]).to eq("Epic archived.")
      expect(epic.reload).to be_archived
    end

    it "returns 404 for another user's Epic" do
      sign_in_as(user)
      other_user = Factories.user
      other_repo = Factories.repository(user: other_user)
      epic = Factories.epic(user: other_user, repository: other_repo, state: "ready")

      patch archive_epic_path(epic)

      expect(response).to have_http_status(:not_found)
      expect(epic.reload).to be_ready
    end

    it "redirects neutrally when the Epic is already archived" do
      sign_in_as(user)
      epic = Factories.epic(user: user, repository: repo, state: "ready")
      epic.archive!

      patch archive_epic_path(epic)

      expect(response).to redirect_to(epics_path)
      expect(flash[:notice]).to eq("Epic already archived.")
      expect(epic.reload).to be_archived
    end
  end

  describe "PATCH /epics/:id/state" do
    it "advances a backlog Epic to ready through an allowed transition" do
      sign_in_as(user)
      epic = Factories.epic(user: user, repository: repo, state: "backlog")

      patch state_epic_path(epic),
            params: { target_state: "ready" },
            headers: { "HTTP_REFERER" => epic_path(epic) }

      expect(response).to redirect_to(epic_path(epic))
      expect(flash[:notice]).to eq("Epic updated.")
      expect(epic.reload).to be_ready
    end

    it "marks an in-progress Epic done when its child Jobs are complete" do
      sign_in_as(user)
      epic = Factories.epic(user: user, repository: repo, state: "in_progress")
      Factories.job_record(user: user, repository: repo, epic: epic, state: "closed", closure_reason: "pr_merged")

      patch state_epic_path(epic),
            params: { target_state: "done" },
            headers: { "HTTP_REFERER" => epic_path(epic) }

      expect(response).to redirect_to(epic_path(epic))
      expect(flash[:notice]).to eq("Epic updated.")
      expect(epic.reload).to be_done
      expect(epic.done_at).to be_present
    end
  end

  describe "GET /epics/new" do
    it "requires authentication" do
      user
      get new_epic_path

      expect(response).to redirect_to(new_session_path)
    end

    it "serves the React app shell" do
      sign_in_as(user)

      get new_epic_path

      expect(response).to be_successful
      expect(response.body).to include('id="syrus-spa-root"')
    end
  end

  describe "GET /epics/:id/edit" do
    it "serves the React app shell" do
      sign_in_as(user)
      epic = Factories.epic(user: user, repository: repo)

      get edit_epic_path(epic)

      expect(response).to be_successful
      expect(response.body).to include('id="syrus-spa-root"')
    end
  end

  describe "legacy Epic page endpoints" do
    it "does not route retired HTML page and form endpoints" do
      expect {
        Rails.application.routes.recognize_path("/epics/new/legacy", method: :get)
      }.to raise_error(ActionController::RoutingError)
      expect {
        Rails.application.routes.recognize_path("/epics/1/legacy", method: :get)
      }.to raise_error(ActionController::RoutingError)
      expect {
        Rails.application.routes.recognize_path("/epics/1/edit/legacy", method: :get)
      }.to raise_error(ActionController::RoutingError)
      expect {
        Rails.application.routes.recognize_path("/epics", method: :post)
      }.to raise_error(ActionController::RoutingError)
      expect {
        Rails.application.routes.recognize_path("/epics/1", method: :patch)
      }.to raise_error(ActionController::RoutingError)
    end
  end

  describe "POST /smart_folders with subject_type=epic" do
    it "saves a non-empty Epic filter as an Epic smart folder" do
      sign_in_as(user)
      filter = {
        "and" => [
          { "field" => "state", "op" => "is", "value" => "ready" },
          { "field" => "title", "op" => "contains", "value" => "Forum" }
        ]
      }

      post smart_folders_path, params: {
        subject_type: "epic",
        filter: filter.to_json,
        smart_folder: { name: "Ready forums" }
      }

      folder = user.smart_folders.find_by!(name: "Ready forums")
      expect(folder.subject_type).to eq("epic")
      expect(folder.filter).to eq(filter)
      expect(response).to redirect_to(dashboard_epics_path(smart_folder_id: folder.id))
    end
  end

  describe "GET /epics/:id" do
    it "requires authentication" do
      epic = Factories.epic(user: user, repository: repo)

      get epic_path(epic)

      expect(response).to redirect_to(new_session_path)
    end

    it "serves the React app shell" do
      sign_in_as(user)
      epic = Factories.epic(user: user, repository: repo, title: "Restore forum")

      get epic_path(epic)

      expect(response).to be_successful
      expect(response.body).to include('id="syrus-spa-root"')
    end
  end

  describe "GET /epics/:id/graph" do
    it "does not route the retired Turbo drawer endpoint" do
      expect {
        Rails.application.routes.recognize_path("/epics/1/graph", method: :get)
      }.to raise_error(ActionController::RoutingError)
    end
  end
end
