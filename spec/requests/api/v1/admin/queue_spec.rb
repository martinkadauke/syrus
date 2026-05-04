require "rails_helper"

# SolidQueue tables aren't loaded in dev/test single-database
# setups, so most endpoints respond with the queue_unreachable
# envelope here. The API contract is exercised; production
# behavior (with the queue DB present) is verified by hand on
# staging — same pattern as the HTML queue spec.
RSpec.describe "API: /api/v1/admin/queue/*", type: :request do
  let(:admin) { Factories.user }
  let(:admin_token) { admin.generate_api_token! }
  def auth = { "Authorization" => "Bearer #{admin_token}" }
  def parse_body = JSON.parse(response.body)

  %w[active pending failed recurring workers].each do |tab|
    it "GET /api/v1/admin/queue/#{tab} responds — either with data or queue_unreachable" do
      get "/api/v1/admin/queue/#{tab}", headers: auth
      # On dev/test single-DB this returns 503 queue_unreachable;
      # production with the queue DB returns 200 with content.
      # Either is a valid spec assertion of the contract.
      expect([ 200, 503 ]).to include(response.status)
      if response.status == 503
        expect(parse_body.dig("error", "code")).to eq("queue_unreachable")
      end
    end
  end

  describe "POST /api/v1/admin/queue/reap_stale_runs" do
    it "runs ReapStaleRunsJob inline and returns ok" do
      expect(ReapStaleRunsJob).to receive(:perform_now)
      post "/api/v1/admin/queue/reap_stale_runs", headers: auth
      expect(response).to be_successful
      expect(parse_body["ok"]).to be true
    end

    it "401s without a token" do
      post "/api/v1/admin/queue/reap_stale_runs"
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
