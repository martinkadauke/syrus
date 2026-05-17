require "rails_helper"

# Chat whiteboards now have their own request spec under
# spec/requests/chat_whiteboards_spec.rb — only repo whiteboard
# endpoints live here.
RSpec.describe "Repository whiteboards", type: :request do
  let(:user) { Factories.user }
  let(:repo) { Factories.repository(user: user, owner: "acme", name: "widgets") }

  before { sign_in_as(user) }

  def parse_body = JSON.parse(response.body)

  describe "GET /repositories/:repository_id/whiteboard" do
    it "creates and returns an empty scene for the repository" do
      expect {
        get repository_whiteboard_path(repo), as: :json
      }.to change(RepositoryWhiteboard, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(parse_body).to eq(
        "scene_json" => { "elements" => [] },
        "version" => 0
      )
    end
  end

  describe "PATCH /repositories/:repository_id/whiteboard" do
    it "persists elements and increments the version" do
      elements = [
        {
          id: "rect-1",
          type: "rectangle",
          x: 10,
          y: 20,
          width: 100,
          height: 80
        }
      ]

      patch repository_whiteboard_path(repo),
            params: { elements: elements, expected_version: 0 },
            as: :json

      expect(response).to have_http_status(:ok)
      expect(parse_body).to eq(
        "scene_json" => { "elements" => elements.map(&:stringify_keys) },
        "version" => 1
      )

      get repository_whiteboard_path(repo), as: :json

      expect(parse_body).to eq(
        "scene_json" => { "elements" => elements.map(&:stringify_keys) },
        "version" => 1
      )
    end

    it "returns the current scene on a stale expected_version without overwriting" do
      whiteboard = repo.create_repository_whiteboard!(
        scene_json: { "elements" => [ { "id" => "current", "type" => "ellipse" } ] },
        version: 2
      )

      patch repository_whiteboard_path(repo),
            params: {
              elements: [ { id: "stale", type: "rectangle" } ],
              expected_version: 1
            },
            as: :json

      expect(response).to have_http_status(:conflict)
      expect(parse_body).to eq(
        "scene_json" => { "elements" => [ { "id" => "current", "type" => "ellipse" } ] },
        "version" => 2
      )
      expect(whiteboard.reload.elements).to eq([ { "id" => "current", "type" => "ellipse" } ])
    end
  end
end
