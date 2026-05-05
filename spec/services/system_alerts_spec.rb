require "rails_helper"

RSpec.describe SystemAlerts do
  describe ".active_for" do
    it "returns no alerts for a healthy user" do
      user = Factories.user
      expect(described_class.active_for(user: user)).to be_empty
    end

    it "returns no alerts for an anonymous request (user: nil)" do
      expect(described_class.active_for(user: nil)).to eq([])
    end

    it "surfaces a github-token-blocked alert when the user is flagged" do
      user = Factories.user
      user.mark_gh_api_blocked!("Resource not accessible by personal access token")

      alerts = described_class.active_for(user: user)
      expect(alerts.size).to eq(1)
      alert = alerts.first

      expect(alert.severity).to eq(:alarm)
      expect(alert.title).to match(/GitHub API access/i)
      # Verbatim API response is wrapped in <code> for visual contrast
      # with the surrounding prose.
      expect(alert.message).to include("<code>Resource not accessible by personal access token</code>")
      expect(alert.action_steps.size).to be >= 2
      expect(alert.action_steps.join).to match(/scope|read/)
      expect(alert.cta).to eq(text: "Update token", path: "/credentials/edit")
    end

    it "html-escapes the verbatim API reason before wrapping in <code> (untrusted content)" do
      user = Factories.user
      user.mark_gh_api_blocked!("oops <script>alert(1)</script>")
      alert = described_class.active_for(user: user).first
      expect(alert.message).to include("&lt;script&gt;alert(1)&lt;/script&gt;")
      expect(alert.message).not_to include("<script>")
    end

    it "alert id is stable per user — same user, same id, so banners can be deduplicated" do
      user = Factories.user
      user.mark_gh_api_blocked!("anything")
      first  = described_class.active_for(user: user).first
      second = described_class.active_for(user: user).first
      expect(first.id).to eq(second.id)
    end
  end
end
