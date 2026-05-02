require "rails_helper"

RSpec.describe "Credentials", type: :request do
  let(:user) { Factories.user(claude_oauth_token: "sk-existing", github_token: "ghp_existing") }

  it "requires authentication" do
    get edit_credentials_path
    expect(response).to redirect_to(new_session_path)
  end

  context "signed in" do
    before { sign_in_as(user) }

    it "renders the edit form without echoing existing values" do
      get edit_credentials_path
      expect(response).to be_successful
      expect(response.body).not_to include("sk-existing")
      expect(response.body).not_to include("ghp_existing")
      expect(response.body).to include("Currently set")
    end

    it "updates only non-blank fields (write-only)" do
      patch credentials_path, params: { user: { claude_oauth_token: "sk-new", github_token: "" } }
      expect(response).to redirect_to(edit_credentials_path)
      user.reload
      expect(user.claude_oauth_token).to eq("sk-new")
      expect(user.github_token).to eq("ghp_existing")
    end

    it "leaves both unchanged when both fields are blank" do
      patch credentials_path, params: { user: { claude_oauth_token: "", github_token: "" } }
      user.reload
      expect(user.claude_oauth_token).to eq("sk-existing")
      expect(user.github_token).to eq("ghp_existing")
    end
  end
end
