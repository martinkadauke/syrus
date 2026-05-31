require "rails_helper"

RSpec.describe "API: /api/v1/app/chats", type: :request do
  let(:user) { Factories.user(claude_oauth_token: "oat-test") }
  let(:repository) { Factories.repository(user: user, owner: "acme", name: "widgets") }

  def parse_body
    JSON.parse(response.body)
  end

  it "401s with a JSON error when signed out" do
    get "/api/v1/app/chats/new"

    expect(response).to have_http_status(:unauthorized)
    expect(parse_body.dig("error", "code")).to eq("unauthorized")
  end

  it "returns the new chat form payload with active repositories" do
    sign_in_as(user)
    repository
    archived = Factories.repository(user: user, owner: "old", name: "repo")
    archived.archive!
    Factories.repository(user: Factories.user, owner: "other", name: "private")

    get "/api/v1/app/chats/new"

    expect(response).to have_http_status(:ok)
    expect(parse_body["repositories"]).to contain_exactly(include("id" => repository.id, "slug" => "acme/widgets"))
    expect(parse_body.to_s).not_to include("old/repo")
    expect(parse_body.to_s).not_to include("other/private")
    expect(parse_body["repositories_path"]).to eq(repositories_path)
  end

  it "creates a fresh chat with an optional repository attachment" do
    sign_in_as(user)

    expect {
      post "/api/v1/app/chats", params: { repository_id: repository.id }
    }.to change(ChatSession, :count).by(1)

    expect(response).to have_http_status(:created)
    chat = ChatSession.last
    expect(chat.user).to eq(user)
    expect(chat.attached_repositories).to contain_exactly(repository)
    expect(parse_body).to include("message" => "Chat created.", "redirect_to" => chat_path(chat))
    expect(parse_body.dig("chat", "repository", "slug")).to eq("acme/widgets")
  end

  it "creates the first message and enqueues a turn" do
    sign_in_as(user)

    expect {
      post "/api/v1/app/chats", params: { repository_id: repository.id, chat_message: { text: "Map auth" } }
    }.to change(ChatSession, :count).by(1)
      .and change(ChatMessage, :count).by(1)
      .and have_enqueued_job(ChatTurnJob)

    chat = ChatSession.last
    expect(chat.messages.last.content).to eq("text" => "Map auth")
    expect(parse_body).to include("message" => "Message sent.", "redirect_to" => chat_path(chat))
  end

  it "creates a chat without a repository attachment" do
    sign_in_as(user)

    expect {
      post "/api/v1/app/chats", params: { chat_message: { text: "Map tkadauke/syrus" } }
    }.to change(ChatSession, :count).by(1)
      .and change(ChatMessage, :count).by(1)
      .and have_enqueued_job(ChatTurnJob)

    chat = ChatSession.last
    expect(chat.attached_repositories).to be_empty
    expect(chat.messages.last.content).to eq("text" => "Map tkadauke/syrus")
  end

  it "does not attach another user's repository" do
    sign_in_as(user)
    foreign = Factories.repository(user: Factories.user)

    expect {
      post "/api/v1/app/chats", params: { repository_id: foreign.id }
    }.not_to change(ChatSession, :count)

    expect(response).to have_http_status(:not_found)
  end
end
