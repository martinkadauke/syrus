require "rails_helper"

RSpec.describe "OAuth: Claude callback", type: :request do
  let(:user) { Factories.user }

  # Runs claude_oauth_start so the session carries verifier + state, then
  # returns the state the callback must echo back.
  def start_flow
    post "/api/v1/app/credentials/claude_oauth_start"
    authorize_url = JSON.parse(response.body)["authorize_url"]
    Rack::Utils.parse_query(URI(authorize_url).query).fetch("state")
  end

  it "exchanges the code, saves the token, and reports success" do
    sign_in_as(user)
    state = start_flow

    stub_request(:post, ClaudeOauth::TOKEN_URL)
      .to_return(status: 200, body: { access_token: "sk-ant-oat01-new" }.to_json, headers: { "Content-Type" => "application/json" })
    probe = CredentialProbe::Result.new(credential: "claude_oauth_token", ok: true, message: "Claude OAuth token is valid.", details: {})
    expect(CredentialProbe).to receive(:call).with(user: user, credential: "claude_oauth_token").and_return(probe)

    get "/oauth/claude/callback", params: { code: "auth-code", state: state }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Claude connected")
    expect(response.body).to include("syrus:claude-oauth")
    expect(user.reload.claude_oauth_token).to eq("sk-ant-oat01-new")
  end

  it "rejects a mismatched state without saving anything" do
    sign_in_as(user)
    start_flow

    get "/oauth/claude/callback", params: { code: "auth-code", state: "wrong-state" }

    expect(response.body).to include("Couldn&#39;t connect Claude").or include("Couldn't connect Claude")
    expect(user.reload.claude_oauth_token).to be_blank
  end

  it "surfaces a provider error from the redirect" do
    sign_in_as(user)
    start_flow

    get "/oauth/claude/callback", params: { error: "access_denied", error_description: "User said no." }

    expect(response.body).to include("User said no.")
    expect(user.reload.claude_oauth_token).to be_blank
  end

  it "requires authentication" do
    get "/oauth/claude/callback", params: { code: "x", state: "y" }

    expect(response).to redirect_to(new_session_path).or have_http_status(:redirect)
  end
end
