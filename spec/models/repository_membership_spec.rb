require "rails_helper"

RSpec.describe RepositoryMembership do
  let(:user) { Factories.user }
  let(:repo) { Factories.repository(user: user) }

  it "accepts a valid role" do
    membership = repo.repository_memberships.build(user: user, role: "owner")
    expect(membership).to be_valid
  end

  it "rejects an unknown role" do
    membership = repo.repository_memberships.build(user: user, role: "admin")
    expect(membership).not_to be_valid
    expect(membership.errors[:role]).to be_present
  end

  describe "installation association" do
    it "can link to an installation" do
      installation = Factories.installation(user: user)
      membership = repo.repository_memberships.create!(user: user, role: "owner", installation: installation)
      expect(membership.installation).to eq(installation)
    end

    it "allows a nil installation" do
      membership = repo.repository_memberships.build(user: user, role: "owner", installation: nil)
      expect(membership).to be_valid
    end

    it "nullifies installation_id when the installation is destroyed" do
      installation = Factories.installation(user: user)
      membership = repo.repository_memberships.create!(user: user, role: "owner", installation: installation)
      installation.destroy!
      expect(membership.reload.installation_id).to be_nil
    end
  end

  describe "agent_provider" do
    it "allows a valid agent provider" do
      membership = repo.repository_memberships.build(user: user, role: "owner", agent_provider: "claude")
      expect(membership).to be_valid
    end

    it "rejects an unknown agent provider" do
      membership = repo.repository_memberships.build(user: user, role: "owner", agent_provider: "oracle")
      expect(membership).not_to be_valid
      expect(membership.errors[:agent_provider]).to be_present
    end

    it "normalizes blank agent_provider to nil" do
      membership = repo.repository_memberships.create!(user: user, role: "owner", agent_provider: "")
      expect(membership.agent_provider).to be_nil
    end

    it "allows a nil agent_provider" do
      membership = repo.repository_memberships.build(user: user, role: "owner", agent_provider: nil)
      expect(membership).to be_valid
    end
  end
end
