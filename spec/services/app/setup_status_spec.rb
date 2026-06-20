require "rails_helper"

RSpec.describe App::SetupStatus do
  it "points a new first user at credentials" do
    user = Factories.user

    payload = described_class.call(user: user)

    expect(payload[:complete]).to eq(false)
    expect(payload[:next_step]).to eq("credentials")
    expect(payload.dig(:credentials, :ready)).to eq(false)
    expect(payload.dig(:system, :ready)).to eq(true)
    expect(payload.dig(:repositories, :active_count)).to eq(0)
    expect(payload.dig(:progress, :completed)).to eq(0)
  end

  it "advances through repository and chat states until the first Epic lands" do
    user = Factories.user(github_token: "ghp_test", claude_oauth_token: "oat-test")
    expect(described_class.call(user: user)[:next_step]).to eq("repository")

    repository = Factories.repository(user: user, owner: "acme", name: "widgets", trigger_label: "syrus")
    repository_payload = described_class.call(user: user)
    expect(repository_payload[:next_step]).to eq("chat")
    expect(repository_payload.dig(:repositories, :first, :slug)).to eq("acme/widgets")
    expect(repository_payload.dig(:repositories, :first, :credential_mode)).to eq("pat")

    # An Epic that has not landed yet keeps the chat step open.
    epic = Factories.epic(user: user, repository: repository, state: "in_progress")
    in_progress_payload = described_class.call(user: user)
    expect(in_progress_payload[:complete]).to eq(false)
    expect(in_progress_payload[:next_step]).to eq("chat")

    epic.update!(state: "done")
    complete_payload = described_class.call(user: user)
    expect(complete_payload[:complete]).to eq(true)
    expect(complete_payload[:next_step]).to eq("complete")
    expect(complete_payload.dig(:progress, :completed)).to eq(3)
  end

  it "reports chat_started and the onboarding chat path once the chat begins" do
    user = Factories.user(github_token: "ghp_test", claude_oauth_token: "oat-test")
    repository = Factories.repository(user: user)

    before = described_class.call(user: user)
    expect(before[:chat_started]).to eq(false)
    expect(before[:onboarding_chat_path]).to be_nil
    expect(before[:next_step]).to eq("chat")

    chat = ChatSession.create!(user: user, repository: repository, onboarding: true)
    after = described_class.call(user: user)
    expect(after[:chat_started]).to eq(true)
    expect(after[:onboarding_chat_path]).to eq("/chats/#{chat.id}")
    expect(after[:next_step]).to eq("epic")
    expect(after[:complete]).to eq(false)
  end

  it "treats a registered GitHub App as ready GitHub credentials" do
    AppSetting.current.update!(github_app_id: 123, github_app_slug: "operator-syrus")
    user = Factories.user(github_token: nil, claude_oauth_token: "oat-test")

    payload = described_class.call(user: user)

    expect(payload[:next_step]).to eq("repository")
    expect(payload.dig(:credentials, :ready)).to eq(true)
    expect(payload.dig(:github_app, :registered)).to eq(true)
    credentials_step = payload.dig(:progress, :steps).find { |step| step[:key] == "credentials" }
    expect(credentials_step).to include(complete: true)
  end
end
