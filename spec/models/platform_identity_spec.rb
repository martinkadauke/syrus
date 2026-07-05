require "rails_helper"

RSpec.describe PlatformIdentity, type: :model do
  let(:owner) { Factories.user }

  it "is valid with required attributes" do
    identity = PlatformIdentity.new(
      user: owner,
      platform: "telegram",
      external_id: "123456789",
      linked_at: Time.current
    )
    expect(identity).to be_valid
  end

  it "requires a user" do
    identity = PlatformIdentity.new(platform: "telegram", external_id: "123", linked_at: Time.current)
    expect(identity).not_to be_valid
    expect(identity.errors[:user]).to be_present
  end

  it "requires a platform" do
    identity = PlatformIdentity.new(user: owner, external_id: "123", linked_at: Time.current)
    expect(identity).not_to be_valid
  end

  it "requires an external_id" do
    identity = PlatformIdentity.new(user: owner, platform: "telegram", linked_at: Time.current)
    expect(identity).not_to be_valid
    expect(identity.errors[:external_id]).to be_present
  end

  it "requires linked_at" do
    identity = PlatformIdentity.new(user: owner, platform: "telegram", external_id: "123")
    expect(identity).not_to be_valid
    expect(identity.errors[:linked_at]).to be_present
  end

  it "rejects unknown platform values" do
    identity = PlatformIdentity.new(user: owner, platform: "discord", external_id: "123", linked_at: Time.current)
    expect(identity).not_to be_valid
  end

  it "enforces uniqueness of external_id scoped to platform" do
    Factories.platform_identity(user: owner, platform: "telegram", external_id: "dup123")
    duplicate = PlatformIdentity.new(
      user: Factories.user,
      platform: "telegram",
      external_id: "dup123",
      linked_at: Time.current
    )
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:external_id]).to include("is already linked to a Syrus account")
  end

  it "allows the same external_id on a different platform" do
    Factories.platform_identity(user: owner, platform: "telegram", external_id: "shared123")
    identity = PlatformIdentity.new(
      user: owner,
      platform: "slack",
      external_id: "shared123",
      linked_at: Time.current
    )
    expect(identity).to be_valid
  end

  it "is destroyed when the user is destroyed" do
    pi = Factories.platform_identity(user: owner)
    expect { owner.destroy! }.to change { PlatformIdentity.count }.by(-1)
    expect { pi.reload }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
