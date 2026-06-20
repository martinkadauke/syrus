require "rails_helper"

RSpec.describe "Admin GitHub App registration", type: :request do
  let(:admin) { Factories.user }
  let(:pem) { OpenSSL::PKey::RSA.generate(2048).to_pem }

  before { sign_in_as(admin) }

  def register_manifest
    get "/api/v1/app/admin/github_app/register"
    JSON.parse(response.body)
  end

  it "serves GitHub App pages through the React shell" do
    get "/admin/github_app/register"

    expect(response).to be_successful
    expect(response.body).to include('id="syrus-spa-root"')
    expect(response.body).not_to include("https://github.com/settings/apps/new?state=")

    get "/admin/github_app/confirm"

    expect(response).to be_successful
    expect(response.body).to include('id="syrus-spa-root"')
  end

  it "exchanges the manifest code and persists encrypted credentials" do
    state = register_manifest.fetch("github_manifest_url").match(%r{settings/apps/new\?state=([^"]+)})[1]
    stub_request(:post, "https://api.github.com/app-manifests/temp-code/conversions")
      .to_return(
        status: 201,
        headers: { "Content-Type" => "application/json" },
        body: {
          id: 12345,
          slug: "operator-syrus",
          pem: pem
        }.to_json
      )

    expect {
      get "/admin/github_app/callback", params: { code: "temp-code", state: state }
    }.to have_enqueued_job(SyncInstallationsJob).with(admin.id)

    settings = AppSetting.current.reload
    expect(settings.github_app_id).to eq(12345)
    expect(settings.github_app_slug).to eq("operator-syrus")
    expect(settings.github_app_private_key_pem).to eq(pem)
    expect(settings.github_app_registered_at).to be_present
    expect(response).to redirect_to(admin_github_app_confirm_path)
  end

  it "renders a minimal close-me page (not the admin redirect) for the onboarding origin" do
    get "/api/v1/app/admin/github_app/register", params: { origin: "onboarding" }
    state = JSON.parse(response.body).fetch("github_manifest_url").match(%r{settings/apps/new\?state=([^"]+)})[1]
    stub_request(:post, "https://api.github.com/app-manifests/temp-code/conversions")
      .to_return(status: 201, headers: { "Content-Type" => "application/json" }, body: { id: 99, slug: "operator-syrus", pem: pem }.to_json)

    get "/admin/github_app/callback", params: { code: "temp-code", state: state }

    expect(response).to have_http_status(:ok)
    expect(response).not_to redirect_to(admin_github_app_confirm_path)
    expect(response.body).to include("GitHub App registered")
    expect(response.body).to include("close this window")
    expect(response.body).not_to include('id="syrus-spa-root"')
    expect(AppSetting.current.reload.github_app_id).to eq(99)
  end

  it "rejects callbacks with a mismatched state" do
    register_manifest

    expect {
      get "/admin/github_app/callback", params: { code: "temp-code", state: "wrong" }
    }.not_to change { AppSetting.current.reload.github_app_id }
    expect(response).to redirect_to(admin_github_app_register_path)
  end

  it "does not expose a GitHub App webhook route" do
    post "/github_app/webhook"

    expect(response).to have_http_status(:not_found)
  end
end
