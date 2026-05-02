require "rails_helper"

RSpec.describe "Invitations", type: :request do
  let(:admin) { Factories.user }              # first user → admin
  let(:non_admin) { Factories.user }          # second user → not admin

  it "requires authentication" do
    get invitations_path
    expect(response).to redirect_to(new_session_path)
  end

  context "as a non-admin" do
    before { admin; sign_in_as(non_admin) }  # force admin to be created first

    it "blocks index" do
      get invitations_path
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to match(/Admin access/)
    end

    it "blocks create" do
      expect {
        post invitations_path, params: { invitation: { email_address: "x@example.com" } }
      }.not_to change(Invitation, :count)
    end
  end

  context "as an admin" do
    before { admin; sign_in_as(admin) }

    it "lists pending invitations" do
      pending = Invitation.create!(invited_by: admin, email_address: "guest@example.com")
      get invitations_path
      expect(response.body).to include("guest@example.com")
      expect(response.body).to include(pending.token)
    end

    it "creates an invitation tied to the current admin" do
      expect {
        post invitations_path, params: { invitation: { email_address: "guest@example.com" } }
      }.to change(Invitation, :count).by(1)
      expect(Invitation.last.invited_by).to eq(admin)
    end

    it "revokes (destroys) an invitation" do
      inv = Invitation.create!(invited_by: admin, email_address: "guest@example.com")
      expect {
        delete invitation_path(inv)
      }.to change(Invitation, :count).by(-1)
    end
  end
end
