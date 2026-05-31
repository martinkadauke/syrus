require "rails_helper"

RSpec.describe "Smart folders", type: :request do
  let(:user) { Factories.user }

  before { sign_in_as(user) }

  describe "POST /smart_folders" do
    it "creates an Epic smart folder and redirects to the Epic dashboard" do
      post smart_folders_path, params: {
        subject_type: "epic",
        state: "ready",
        smart_folder: { name: "Ready Epics" }
      }

      folder = user.smart_folders.find_by!(name: "Ready Epics")
      expect(folder.subject_type).to eq("epic")
      expect(folder.filter).to eq(
        "and" => [
          { "field" => "state", "op" => "is", "value" => "ready" }
        ]
      )
      expect(response).to redirect_to(dashboard_epics_path(smart_folder_id: folder.id))
    end

    it "creates a Workflow smart folder and redirects to the Workflow dashboard" do
      post smart_folders_path, params: {
        subject_type: "workflow",
        state: "queued",
        smart_folder: { name: "Queued Workflows" }
      }

      folder = user.smart_folders.find_by!(name: "Queued Workflows")
      expect(folder.subject_type).to eq("workflow")
      expect(folder.filter).to eq(
        "and" => [
          { "field" => "state", "op" => "is", "value" => "queued" }
        ]
      )
      expect(response).to redirect_to(dashboard_workflows_path(smart_folder_id: folder.id))
    end
  end

  describe "GET /smart_folders" do
    it "serves the React smart folders shell" do
      get smart_folders_path, params: { subject_type: "epic" }

      expect(response).to be_successful
      expect(response.body).to include('id="syrus-spa-root"')
    end

    it "does not route the retired legacy HTML management endpoints" do
      expect {
        Rails.application.routes.recognize_path("/smart_folders/legacy", method: :get)
      }.to raise_error(ActionController::RoutingError)
      expect {
        Rails.application.routes.recognize_path("/smart_folders/legacy/1", method: :patch)
      }.to raise_error(ActionController::RoutingError)
      expect {
        Rails.application.routes.recognize_path("/smart_folders/legacy/1", method: :delete)
      }.to raise_error(ActionController::RoutingError)
      expect {
        Rails.application.routes.recognize_path("/smart_folders/1", method: :patch)
      }.to raise_error(ActionController::RoutingError)
      expect {
        Rails.application.routes.recognize_path("/smart_folders/1", method: :delete)
      }.to raise_error(ActionController::RoutingError)
    end
  end
end
