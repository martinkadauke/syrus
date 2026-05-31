require "rails_helper"

RSpec.describe "Job attachments", type: :request do
  it "does not route the retired legacy HTML attachment endpoints" do
    expect {
      Rails.application.routes.recognize_path("/jobs/1/attachments", method: :post)
    }.to raise_error(ActionController::RoutingError)

    expect {
      Rails.application.routes.recognize_path("/jobs/1/attachments/2", method: :delete)
    }.to raise_error(ActionController::RoutingError)
  end
end
