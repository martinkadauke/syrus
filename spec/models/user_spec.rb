require "rails_helper"

RSpec.describe User do
  let(:attrs) { { email_address: "user@example.com", password: "supersecret" } }

  describe "first-signup admin rule" do
    it "promotes the very first user to admin" do
      user = User.create!(attrs)
      expect(user.admin?).to be true
    end

    it "does not promote subsequent users" do
      User.create!(attrs)
      second = User.create!(attrs.merge(email_address: "two@example.com"))
      expect(second.admin?).to be false
    end

    it "does not re-promote on re-save" do
      User.create!(attrs)
      second = User.create!(attrs.merge(email_address: "two@example.com"))
      second.update!(email_address: "two-renamed@example.com")
      expect(second.admin?).to be false
    end
  end

  describe "encrypted credentials" do
    it "round-trips claude_oauth_token and github_token" do
      user = User.create!(attrs.merge(claude_oauth_token: "oat-abc", github_token: "ghp_xyz"))
      reloaded = User.find(user.id)
      expect(reloaded.claude_oauth_token).to eq("oat-abc")
      expect(reloaded.github_token).to eq("ghp_xyz")
    end

    it "stores ciphertext, not plaintext, in the column" do
      user = User.create!(attrs.merge(claude_oauth_token: "oat-secret"))
      raw = User.connection.select_value("SELECT claude_oauth_token FROM users WHERE id = #{user.id}")
      expect(raw).not_to include("oat-secret")
    end
  end

  describe "email normalization" do
    it "downcases and strips whitespace" do
      user = User.create!(attrs.merge(email_address: "  Mixed@Example.com  "))
      expect(user.email_address).to eq("mixed@example.com")
    end
  end

  describe "agent_max_turns" do
    it "defaults to 200 for new users" do
      user = User.create!(attrs)
      expect(user.agent_max_turns).to eq(200)
    end

    it "accepts a value within range" do
      user = User.create!(attrs.merge(agent_max_turns: 500))
      expect(user.reload.agent_max_turns).to eq(500)
    end

    it "accepts 0 as the special-case 'no cap' value" do
      user = User.create!(attrs.merge(agent_max_turns: 0))
      expect(user.reload.agent_max_turns).to eq(0)
    end

    it "rejects negative values" do
      user = User.new(attrs.merge(agent_max_turns: -1))
      expect(user).not_to be_valid
      expect(user.errors[:agent_max_turns]).to be_present
    end

    it "rejects values above the range" do
      user = User.new(attrs.merge(agent_max_turns: User::AGENT_MAX_TURNS_RANGE.last + 1))
      expect(user).not_to be_valid
      expect(user.errors[:agent_max_turns]).to be_present
    end

    it "rejects non-integer values" do
      user = User.new(attrs.merge(agent_max_turns: 3.5))
      expect(user).not_to be_valid
      expect(user.errors[:agent_max_turns]).to be_present
    end
  end
end
