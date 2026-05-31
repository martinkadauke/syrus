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

  it "returns the chat rendering payload" do
    sign_in_as(user)
    document = repository.repository_documents.create!(
      user: user,
      kind: "google_doc",
      title: "Launch notes",
      google_docs_url: "https://docs.google.com/document/d/launch/edit"
    )
    chat = ChatSession.create!(
      user: user,
      repository: repository,
      cumulative_input_tokens: 12_400,
      cumulative_output_tokens: 3_200,
      cumulative_cost_usd: 0.012345,
      last_message_at: Time.current
    )
    message = chat.messages.create!(role: "assistant", content: { "text" => "Discuss **aqueducts**." })
    message.bookmarks.create!(label: "Aqueducts", kind: "topic")
    chat.create_whiteboard!(scene_json: { "elements" => [ { "id" => "box-1", "type" => "rectangle" } ] }, version: 2)

    get "/api/v1/app/chats/#{chat.id}"

    expect(response).to have_http_status(:ok)
    body = parse_body
    expect(body.dig("chat", "repository", "slug")).to eq("acme/widgets")
    expect(body.dig("chat", "cumulative_input_tokens")).to eq(12_400)
    expect(body["chat_available"]).to eq(true)
    expect(body["turn_in_flight"]).to eq(false)
    expect(body["bookmarks"]).to contain_exactly(include("label" => "Aqueducts", "chat_message_id" => message.id))
    expect(body["messages"]).to contain_exactly(include(
      "type" => "message",
      "id" => message.id,
      "role" => "assistant",
      "text" => "Discuss **aqueducts**."
    ))
    expect(body["messages"].first).not_to have_key("html")
    expect(body["documents_in_scope"]).to contain_exactly(include("title" => document.title, "repository_slug" => "acme/widgets"))
    expect(body.dig("whiteboard", "version")).to eq(2)
    expect(body.dig("whiteboard", "elements", 0, "id")).to eq("box-1")
    expect(body.dig("paths", "app_messages_path")).to eq("/api/v1/app/chats/#{chat.id}/messages")
    expect(body.dig("paths", "app_message_path")).to eq("/api/v1/app/chats/#{chat.id}/message")
  end

  it "returns older messages as typed JSON for frontend rendering" do
    sign_in_as(user)
    chat = ChatSession.create!(user: user, repository: repository, last_message_at: Time.current)
    messages = 40.times.map { |i| chat.messages.create!(role: "user", content: { "text" => "msg-#{i}" }) }

    get "/api/v1/app/chats/#{chat.id}/messages", params: { before: messages[30].id }

    expect(response).to have_http_status(:ok)
    body = parse_body
    expect(body["has_more_older"]).to eq(false)
    expect(body["messages"].map { |message| message.fetch("id") }).to eq(messages.first(30).map(&:id))
    expect(body["messages"].first).to include(
      "type" => "message",
      "role" => "user",
      "text" => "msg-0"
    )
    expect(body["messages"].first).not_to have_key("html")
  end

  it "keeps proposal bodies as text instead of pre-rendered HTML" do
    sign_in_as(user)
    chat = ChatSession.create!(user: user, repository: repository, last_message_at: Time.current)
    proposal = ChatProposal.create!(
      chat_session: chat,
      slug: "auth-map",
      title: "Map auth flow",
      body: "Trace **auth** and `<script>`."
    )
    chat.messages.create!(role: "assistant", proposal: proposal, content: { "text" => "Proposal proposed." })

    get "/api/v1/app/chats/#{chat.id}"

    proposal_payload = parse_body["messages"].first.fetch("proposal")
    expect(proposal_payload).to include("body" => "Trace **auth** and `<script>`.")
    expect(proposal_payload).not_to have_key("body_html")
  end

  it "groups tool calls in the chat rendering payload" do
    sign_in_as(user)
    chat = ChatSession.create!(user: user, repository: repository, last_message_at: Time.current)
    chat.messages.create!(role: "tool_use", tool_name: "Read", content: { "input" => { "file_path" => "a.py" } })
    chat.messages.create!(role: "tool_result", tool_name: "Read", content: { "result" => [ { "type" => "text", "text" => "first" } ] })
    chat.messages.create!(role: "tool_use", tool_name: "Read", content: { "input" => { "file_path" => "b.py" } })
    chat.messages.create!(role: "tool_result", tool_name: "Read", content: { "result" => [ { "type" => "text", "text" => "second" } ] })

    get "/api/v1/app/chats/#{chat.id}"

    group = parse_body["messages"].sole
    expect(group).to include("type" => "tool_group", "tool" => "Read")
    expect(group["calls"]).to contain_exactly(
      include("detail" => "a.py", "result_body" => "first"),
      include("detail" => "b.py", "result_body" => "second")
    )
  end

  it "returns system message summaries and proposal cards" do
    sign_in_as(user)
    chat = ChatSession.create!(user: user, repository: repository, last_message_at: Time.current)
    proposal = ChatProposal.create!(
      chat_session: chat,
      slug: "auth-map",
      title: "Map auth flow",
      body: "Trace the auth flow."
    )
    chat.messages.create!(role: "assistant", proposal: proposal, content: { "text" => "Proposal proposed." })
    chat.messages.create!(
      role: "system",
      content: {
        "text" => "[result] subtype=success, is_error=false, turns=4, duration_ms=170223, total_cost_usd=0.37236969999999997"
      }
    )

    get "/api/v1/app/chats/#{chat.id}"

    proposal_message = parse_body["messages"].first
    expect(proposal_message.dig("proposal", "title")).to eq("Map auth flow")
    expect(proposal_message.dig("proposal", "confirm_path")).to eq(chat_proposal_confirm_path(chat, proposal))
    system_message = parse_body["messages"].second
    expect(system_message.dig("system", "body")).to include("Agent run succeeded", "$0.37")
    expect(system_message.dig("system", "body")).not_to include("0.37236969999999997")
  end

  it "appends a message through the app API and returns the refreshed payload" do
    sign_in_as(user)
    chat = ChatSession.create!(user: user, repository: repository, last_message_at: 1.day.ago)

    expect {
      post "/api/v1/app/chats/#{chat.id}/message", params: { chat_message: { text: "Now inspect proposals" } }
    }.to change { chat.messages.count }.by(1)
      .and have_enqueued_job(ChatTurnJob).with(chat.id, kind_of(Integer))

    expect(response).to have_http_status(:ok)
    expect(chat.reload.last_message_at).to be > 1.minute.ago
    expect(parse_body["message"]).to eq("Message sent.")
    expect(parse_body["turn_in_flight"]).to eq(true)
  end

  it "returns a validation error for blank chat messages" do
    sign_in_as(user)
    chat = ChatSession.create!(user: user, repository: repository, last_message_at: Time.current)

    expect {
      post "/api/v1/app/chats/#{chat.id}/message", params: { chat_message: { text: "  " } }
    }.not_to change(ChatMessage, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(parse_body.dig("error", "message")).to eq("Message cannot be blank.")
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
