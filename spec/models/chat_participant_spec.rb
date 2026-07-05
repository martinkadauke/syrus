require "rails_helper"

RSpec.describe ChatParticipant do
  let(:repo) { Factories.repository }
  let(:owner) { repo.user }
  let(:session) { ChatSession.create!(user: owner) }
  let(:other_user) { Factories.user }

  it "creates with valid attributes" do
    participant = described_class.new(
      chat_session: session,
      user: other_user,
      role: "member",
      joined_at: Time.current
    )

    expect(participant).to be_valid
  end

  it "sets joined_at automatically on create" do
    participant = described_class.create!(chat_session: session, user: other_user, role: "member")

    expect(participant.joined_at).to be_present
  end

  it "requires a chat_session" do
    participant = described_class.new(user: other_user, role: "owner")

    expect(participant).not_to be_valid
    expect(participant.errors[:chat_session]).to be_present
  end

  it "requires a user" do
    participant = described_class.new(chat_session: session, role: "owner")

    expect(participant).not_to be_valid
    expect(participant.errors[:user]).to be_present
  end

  it "rejects unknown roles" do
    participant = described_class.new(chat_session: session, user: other_user, role: "viewer")

    expect(participant).not_to be_valid
    expect(participant.errors[:role]).to be_present
  end

  it "enforces uniqueness of user per chat session" do
    # owner participant already exists from the after_create callback
    duplicate = described_class.new(chat_session: session, user: owner, role: "member")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:user_id]).to be_present
  end

  it "allows the same user in different sessions" do
    other_session = ChatSession.create!(user: owner)

    expect(other_session.chat_participants.find_by(user: other_user)).to be_nil
    expect(described_class.create!(chat_session: other_session, user: other_user, role: "member")).to be_persisted
  end
end
