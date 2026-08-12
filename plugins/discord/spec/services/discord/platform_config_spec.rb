require "rails_helper"

RSpec.describe Discord::PlatformConfig do
  describe "#configured?" do
    it "is false when discord_bot_token is blank" do
      AppSetting.current.update_column(:discord_bot_token, nil)

      expect(described_class.new.configured?).to be false
    end

    it "is true when discord_bot_token is present" do
      AppSetting.current.update!(discord_bot_token: "bot-token")

      expect(described_class.new.configured?).to be true
    end
  end

  describe "#instructions" do
    it "tells the user to DM /link <token> to the bot" do
      instructions = described_class.new.instructions("tok123")

      expect(instructions[:text]).to eq("Send /link tok123 to the Syrus bot on Discord")
    end
  end
end
