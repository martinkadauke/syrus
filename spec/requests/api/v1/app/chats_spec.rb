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

  it "returns the chat data payload with raw messages" do
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
      "tool_name" => nil,
      "content" => { "text" => "Discuss **aqueducts**." },
      "text" => "Discuss **aqueducts**."
    ))
    expect(body["messages"].first).not_to have_key("html")
    expect(body["documents_in_scope"]).to contain_exactly(include("title" => document.title, "repository_slug" => "acme/widgets"))
    expect(body.dig("whiteboard", "version")).to eq(2)
    expect(body.dig("whiteboard", "elements", 0, "id")).to eq("box-1")
    expect(body.dig("paths", "app_messages_path")).to eq("/api/v1/app/chats/#{chat.id}/messages")
    expect(body.dig("paths", "app_message_path")).to eq("/api/v1/app/chats/#{chat.id}/message")
    expect(body.dig("paths", "app_attachments_path")).to eq("/api/v1/app/chats/#{chat.id}/attachments")
    expect(body.dig("paths", "app_whiteboard_path")).to eq("/api/v1/app/chats/#{chat.id}/whiteboard")
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
      "content" => { "text" => "msg-0" },
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

  it "returns tool calls as raw chronological messages for frontend rendering" do
    sign_in_as(user)
    chat = ChatSession.create!(user: user, repository: repository, last_message_at: Time.current)
    first_call = chat.messages.create!(role: "tool_use", tool_name: "Read", content: { "input" => { "file_path" => "a.py" } })
    first_result = chat.messages.create!(role: "tool_result", tool_name: "Read", content: { "result" => [ { "type" => "text", "text" => "first" } ] })
    second_call = chat.messages.create!(role: "tool_use", tool_name: "Read", content: { "input" => { "file_path" => "b.py" } })
    second_result = chat.messages.create!(role: "tool_result", tool_name: "Read", content: { "result" => [ { "type" => "text", "text" => "second" } ] })

    get "/api/v1/app/chats/#{chat.id}"

    expect(parse_body["messages"].map { |message| message.fetch("id") }).to eq(
      [ first_call.id, first_result.id, second_call.id, second_result.id ]
    )
    expect(parse_body["messages"].first).to include(
      "type" => "message",
      "role" => "tool_use",
      "tool_name" => "Read",
      "content" => { "input" => { "file_path" => "a.py" } }
    )
    expect(parse_body["messages"].second).to include(
      "type" => "message",
      "role" => "tool_result",
      "tool_name" => "Read",
      "content" => { "result" => [ { "type" => "text", "text" => "first" } ] }
    )
  end

  it "returns raw system messages and proposal card data" do
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
    expect(proposal_message.dig("proposal", "app_confirm_path")).to eq("/api/v1/app/chats/#{chat.id}/proposals/#{proposal.id}/confirm")
    system_message = parse_body["messages"].second
    expect(system_message).to include(
      "role" => "system",
      "content" => { "text" => "[result] subtype=success, is_error=false, turns=4, duration_ms=170223, total_cost_usd=0.37236969999999997" }
    )
    expect(system_message).not_to have_key("system")
  end

  it "creates a manual bookmark through the app API" do
    sign_in_as(user)
    chat = ChatSession.create!(user: user, repository: repository, last_message_at: Time.current)
    message = chat.messages.create!(role: "assistant", content: { "text" => "Build aqueducts." })

    expect {
      post "/api/v1/app/chats/#{chat.id}/bookmarks", params: { message_id: message.id, chat_bookmark: { label: "Aqueducts" } }
    }.to change(ChatBookmark, :count).by(1)

    expect(response).to have_http_status(:ok)
    expect(parse_body["message"]).to eq("Bookmarked Aqueducts.")
    expect(parse_body["bookmarks"]).to contain_exactly(include("label" => "Aqueducts", "chat_message_id" => message.id))
  end

  it "adds and removes attachments through the app API" do
    sign_in_as(user)
    chat = ChatSession.create!(user: user, last_message_at: Time.current)

    expect {
      post "/api/v1/app/chats/#{chat.id}/attachments", params: { attachable_type: "Repository", attachable_id: repository.id }
    }.to change(ChatAttachment, :count).by(1)

    expect(response).to have_http_status(:ok)
    attachment = chat.reload.chat_attachments.sole
    expect(attachment.attachable).to eq(repository)
    expect(parse_body["message"]).to eq("acme/widgets attached.")
    expect(parse_body.dig("attachment_groups", "repositories")).to contain_exactly(include(
      "label" => "acme/widgets",
      "app_detach_path" => "/api/v1/app/chats/#{chat.id}/attachments/#{attachment.id}"
    ))

    expect {
      delete "/api/v1/app/chats/#{chat.id}/attachments/#{attachment.id}"
    }.to change(ChatAttachment, :count).by(-1)

    expect(response).to have_http_status(:ok)
    expect(parse_body["message"]).to eq("acme/widgets detached.")
    expect(parse_body.dig("attachment_groups", "repositories")).to eq([])
  end

  it "does not attach another user's repository through the app API" do
    sign_in_as(user)
    chat = ChatSession.create!(user: user, last_message_at: Time.current)
    foreign = Factories.repository(user: Factories.user)

    expect {
      post "/api/v1/app/chats/#{chat.id}/attachments", params: { attachable_type: "Repository", attachable_id: foreign.id }
    }.not_to change(ChatAttachment, :count)

    expect(response).to have_http_status(:not_found)
  end

  it "confirms and rejects proposals through the app API" do
    sign_in_as(user)
    chat = ChatSession.create!(user: user, repository: repository, last_message_at: Time.current)
    confirmed = chat.proposals.create!(slug: "auth-map", title: "Map auth", body: "Map it.")
    rejected = chat.proposals.create!(slug: "cleanup", title: "Clean up", body: "Sweep it.")
    chat.messages.create!(role: "assistant", proposal: confirmed, content: { "text" => "Proposal proposed." })
    chat.messages.create!(role: "assistant", proposal: rejected, content: { "text" => "Another proposal." })

    expect {
      post "/api/v1/app/chats/#{chat.id}/proposals/#{confirmed.id}/confirm"
    }.to change(Job, :count).by(1)

    expect(response).to have_http_status(:ok)
    expect(parse_body["message"]).to match(/\AProposal confirmed and filed as Job #\d+\.\z/)
    expect(confirmed.reload).to be_confirmed
    expect(parse_body["messages"].first.dig("proposal", "materialized_label")).to eq("Job ##{confirmed.job.id}")

    post "/api/v1/app/chats/#{chat.id}/proposals/#{rejected.id}/reject"

    expect(response).to have_http_status(:ok)
    expect(parse_body["message"]).to eq("Proposal rejected.")
    expect(rejected.reload).to be_rejected
  end

  it "confirms and rejects pending actions through the app API" do
    sign_in_as(user)
    chat = ChatSession.create!(user: user, repository: repository, last_message_at: Time.current)
    job_to_cancel = Factories.job(repository: repository)
    job_to_keep = Factories.job(repository: repository, issue_number: 43)
    confirm_action = chat.pending_actions.create!(action: "cancel_job", payload: { "job_id" => job_to_cancel.id })
    reject_action = chat.pending_actions.create!(action: "cancel_job", payload: { "job_id" => job_to_keep.id })

    get "/api/v1/app/chats/#{chat.id}"

    expect(parse_body["pending_actions"]).to contain_exactly(
      include("id" => confirm_action.id, "label" => "Cancel Job ##{job_to_cancel.id}", "app_confirm_path" => "/api/v1/app/chats/#{chat.id}/pending_actions/#{confirm_action.id}/confirm"),
      include("id" => reject_action.id, "label" => "Cancel Job ##{job_to_keep.id}", "app_cancel_path" => "/api/v1/app/chats/#{chat.id}/pending_actions/#{reject_action.id}")
    )

    post "/api/v1/app/chats/#{chat.id}/pending_actions/#{confirm_action.id}/confirm"

    expect(response).to have_http_status(:ok)
    expect(parse_body["message"]).to eq("Pending action confirmed.")
    expect(confirm_action.reload).to be_confirmed
    expect(job_to_cancel.reload).to be_closed

    delete "/api/v1/app/chats/#{chat.id}/pending_actions/#{reject_action.id}"

    expect(response).to have_http_status(:ok)
    expect(parse_body["message"]).to eq("Pending action rejected.")
    expect(reject_action.reload).to be_rejected
    expect(job_to_keep.reload).to be_open
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
