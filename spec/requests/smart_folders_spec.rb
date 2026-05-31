require "rails_helper"

RSpec.describe "Smart folders", type: :request do
  let(:user) { Factories.user }

  before { sign_in_as(user) }

  describe "GET /smart_folders" do
    it "serves the React smart folders shell" do
      get smart_folders_path, params: { subject_type: "epic" }

      expect(response).to be_successful
      expect(response.body).to include('id="syrus-spa-root"')
    end

    it "does not route retired legacy HTML management endpoints" do
      [
        [ :get, "/smart_folders/legacy" ],
        [ :post, "/smart_folders" ],
        [ :patch, "/smart_folders/legacy/1" ],
        [ :delete, "/smart_folders/legacy/1" ],
        [ :patch, "/smart_folders/1" ],
        [ :delete, "/smart_folders/1" ]
      ].each do |method, path|
        expect {
          Rails.application.routes.recognize_path(path, method: method)
        }.to raise_error(ActionController::RoutingError), "#{method.upcase} #{path} should not route"
      end
    end
  end
end
