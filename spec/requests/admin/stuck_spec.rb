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

    it "serves the React stuck-items shell for admins" do
      sign_in_as(admin)
      get "/admin/stuck"
      expect(response).to be_successful
      expect(response.body).to include('id="syrus-spa-root"')
    end
  end

  it "does not route the retired legacy stuck-items endpoint" do
    expect {
      Rails.application.routes.recognize_path("/admin/stuck/legacy", method: :get)
    }.to raise_error(ActionController::RoutingError)
  end
end
