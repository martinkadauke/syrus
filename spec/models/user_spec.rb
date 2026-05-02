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
    it "round-trips claude_api_key and github_token" do
      user = User.create!(attrs.merge(claude_api_key: "sk-abc", github_token: "ghp_xyz"))
      reloaded = User.find(user.id)
      expect(reloaded.claude_api_key).to eq("sk-abc")
      expect(reloaded.github_token).to eq("ghp_xyz")
    end

    it "stores ciphertext, not plaintext, in the column" do
      user = User.create!(attrs.merge(claude_api_key: "sk-secret"))
      raw = User.connection.select_value("SELECT claude_api_key FROM users WHERE id = #{user.id}")
      expect(raw).not_to include("sk-secret")
    end
  end

  describe "email normalization" do
    it "downcases and strips whitespace" do
      user = User.create!(attrs.merge(email_address: "  Mixed@Example.com  "))
      expect(user.email_address).to eq("mixed@example.com")
    end
  end
end
