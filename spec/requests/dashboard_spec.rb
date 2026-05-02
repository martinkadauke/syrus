require "rails_helper"

RSpec.describe "Dashboard", type: :request do
  let(:user)  { Factories.user }
  let(:other) { Factories.user }

  it "requires authentication" do
    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  context "signed in" do
    before { sign_in_as(user) }

    it "lists the current user's recent jobs" do
      mine_repo = Factories.repository(user: user, owner: "acme", name: "widgets")
      Factories.job(repository: mine_repo, issue_number: 7)

      other_repo = Factories.repository(user: other, owner: "globex", name: "things")
      Factories.job(repository: other_repo, issue_number: 99)

      get root_path
      expect(response.body).to include("acme/widgets")
      expect(response.body).to include("#7")
      expect(response.body).not_to include("globex/things")
      expect(response.body).not_to include("#99")
    end

    it "shows the empty state when no jobs exist" do
      get root_path
      expect(response.body).to include("No jobs yet")
    end
  end
end
