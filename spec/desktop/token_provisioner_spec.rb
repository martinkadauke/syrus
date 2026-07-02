# frozen_string_literal: true

require "spec_helper"

# The desktop app mints its menu-bar Bearer token from the signed-in webview
# session (POST /api/v1/app/desktop/api_token) instead of making users paste
# one. These assertions pin the client half of that contract; the Rails half
# lives in spec/requests/api/v1/app/desktop_tokens_spec.rb.
RSpec.describe "desktop token provisioning" do
  let(:desktop_root) { File.expand_path("../../desktop", __dir__) }

  def read(relative_path)
    File.read(File.join(desktop_root, relative_path), encoding: "UTF-8")
  end

  let(:provisioner) { read("electron/tokenProvisioner.ts") }
  let(:main_process) { read("electron/main.ts") }

  it "runs inside the page so the session cookie and CSRF meta tag come for free" do
    expect(provisioner).to include("webContents.executeJavaScript(PROVISION_SCRIPT, true)")
    expect(provisioner).to include('meta[name="csrf-token"]')
    expect(provisioner).to include('"X-CSRF-Token": csrf')
    expect(provisioner).to include('"/api/v1/app/desktop/api_token"')
  end

  it "only provisions for signed-in sessions and never touches the rotate endpoint" do
    expect(provisioner).to include("statusPayload.authenticated !== true")
    expect(provisioner).not_to include("rotate_api_token")
  end

  it "falls back silently for non-admins and skips when credentials already match" do
    expect(provisioner).to include('"forbidden"')
    expect(provisioner).to include('"already-configured"')
  end

  it "persists through main.ts's saveCredentials (validation + cable + 0600 file)" do
    expect(provisioner).not_to include("writeCredentialsFile")
    expect(main_process).to include("maybeProvisionDesktopToken")
    expect(main_process).to match(/did-finish-load[\s\S]*?maybeProvisionDesktopToken/)
  end

  it "only runs against same-origin pages, never the fallback surface" do
    expect(main_process).to include("new URL(handle.window.webContents.getURL()).origin === new URL(serverUrl).origin")
  end
end
