require "rails_helper"

RSpec.describe "Chats", type: :request do
  let(:user) { Factories.user(claude_oauth_token: "oat-test") }
  let(:repo) { Factories.repository(user: user, owner: "acme", name: "widgets") }

  before { sign_in_as(user) }

  describe "GET /chats/new" do
    it "serves the React app shell without creating a chat" do
      repo

      expect {
        get new_chat_path
      }.not_to change(ChatSession, :count)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="syrus-spa-root"')
    end
  end

  describe "GET /chats/:id" do
    it "serves the React app shell" do
      chat = ChatSession.create!(user: user, repository: repo, last_message_at: Time.current)

      get chat_path(chat)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="syrus-spa-root"')
    end
  end

  it "does not route the retired legacy HTML chat endpoints" do
    expect {
      Rails.application.routes.recognize_path("/chats/new/legacy", method: :get)
    }.to raise_error(ActionController::RoutingError)
    expect {
      Rails.application.routes.recognize_path("/chats/1/legacy", method: :get)
    }.to raise_error(ActionController::RoutingError)
    expect {
      Rails.application.routes.recognize_path("/chats", method: :post)
    }.to raise_error(ActionController::RoutingError)
    expect {
      Rails.application.routes.recognize_path("/chats/1/message", method: :post)
    }.to raise_error(ActionController::RoutingError)
    expect {
      Rails.application.routes.recognize_path("/chats/1/messages", method: :get)
    }.to raise_error(ActionController::RoutingError)
  end
end
