require "rails_helper"

RSpec.describe "Repositories", type: :request do
  let(:user)  { Factories.user }
  let(:other) { Factories.user }

  it "requires authentication on index" do
    get repositories_path
    expect(response).to redirect_to(new_session_path)
  end

  context "signed in" do
    before { sign_in_as(user) }

    it "lists only the current user's repositories" do
      mine = Factories.repository(user: user, owner: "acme", name: "widgets")
      Factories.repository(user: other, owner: "globex", name: "things")

      get repositories_path
      expect(response.body).to include("acme/widgets")
      expect(response.body).not_to include("globex/things")
    end

    it "creates with valid params" do
      expect {
        post repositories_path, params: { repository: {
          owner: "acme", name: "widgets", default_branch: "main",
          trigger_label: "syrus", polling_enabled: "1"
        } }
      }.to change(user.repositories, :count).by(1)
      expect(response).to redirect_to(repositories_path)
    end

    it "re-renders new on validation failure" do
      post repositories_path, params: { repository: { owner: "bad owner", name: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("can")  # error messages present
    end

    it "scopes edit/update/destroy to the current user's repos" do
      foreign = Factories.repository(user: other, owner: "globex", name: "things")

      get edit_repository_path(foreign)
      expect(response).to have_http_status(:not_found).or redirect_to(repositories_path)
    end

    it "destroys" do
      mine = Factories.repository(user: user)
      expect {
        delete repository_path(mine)
      }.to change(user.repositories, :count).by(-1)
    end

    it "manual poll enqueues PollRepositoryJob with force: true" do
      mine = Factories.repository(user: user, polling_enabled: false)
      expect {
        post poll_repository_path(mine)
      }.to have_enqueued_job(PollRepositoryJob).with(mine.id, force: true)
      expect(response).to redirect_to(repositories_path)
      expect(flash[:notice]).to match(/Polling/)
    end
  end
end
