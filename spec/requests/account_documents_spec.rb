require "rails_helper"

RSpec.describe "Account documents", type: :request do
  it "does not route the retired legacy account document endpoints" do
    expect {
      Rails.application.routes.recognize_path("/account/documents", method: :post)
    }.to raise_error(ActionController::RoutingError)
    expect {
      Rails.application.routes.recognize_path("/account/documents/1", method: :delete)
    }.to raise_error(ActionController::RoutingError)
  end
end
