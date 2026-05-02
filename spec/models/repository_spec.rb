require "rails_helper"

RSpec.describe Repository do
  let(:owner) { Factories.user }

  it "creates with valid attributes and applies defaults" do
    repo = Repository.create!(user: owner, owner: "acme", name: "widgets")
    expect(repo).to be_persisted
    expect(repo.default_branch).to eq("main")
    expect(repo.polling_enabled).to be false
    expect(repo.trigger_label).to eq("syrus")
  end

  it "rejects malformed owner/name strings" do
    invalid = Repository.new(user: owner, owner: "bad owner", name: "ok")
    expect(invalid).not_to be_valid
    expect(invalid.errors[:owner]).to be_present
  end

  it "enforces uniqueness on (user, owner, name)" do
    Repository.create!(user: owner, owner: "acme", name: "widgets")
    dup = Repository.new(user: owner, owner: "acme", name: "widgets")
    expect(dup).not_to be_valid
    expect(dup.errors[:owner]).to be_present
  end

  it "allows the same repo under a different user" do
    Repository.create!(user: owner, owner: "acme", name: "widgets")
    other = Factories.user
    twin = Repository.new(user: other, owner: "acme", name: "widgets")
    expect(twin).to be_valid
  end

  it "exposes a slug" do
    repo = Repository.new(owner: "acme", name: "widgets")
    expect(repo.slug).to eq("acme/widgets")
  end
end
