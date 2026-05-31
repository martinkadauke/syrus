require "rails_helper"

RSpec.describe "Tags", type: :request do
  let(:user) { Factories.user }

  before { sign_in_as(user) }

  it "serves the React tags shell" do
    get tags_path

    expect(response).to be_successful
    expect(response.body).to include('id="syrus-spa-root"')
  end

  it "does not route the retired legacy HTML tag endpoints" do
    expect {
      Rails.application.routes.recognize_path("/tags/legacy", method: :get)
    }.to raise_error(ActionController::RoutingError)
    expect {
      Rails.application.routes.recognize_path("/tags", method: :post)
    }.to raise_error(ActionController::RoutingError)
    expect {
      Rails.application.routes.recognize_path("/tags/1", method: :patch)
    }.to raise_error(ActionController::RoutingError)
    expect {
      Rails.application.routes.recognize_path("/tags/1", method: :delete)
    }.to raise_error(ActionController::RoutingError)
  end
end
