require "rails_helper"

RSpec.describe "Filter FK options", type: :request do
  describe "GET /filters/fk_options" do
    it "does not route the retired legacy JSON helper" do
      expect {
        Rails.application.routes.recognize_path("/filters/fk_options", method: :get)
      }.to raise_error(ActionController::RoutingError)
    end
  end
end
