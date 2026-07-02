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

  it "never overwrites credentials configured for a different instance" do
    # ~/.syrus/credentials is shared with the syrus CLI; auto-provisioning
    # against instance B must not silently retarget a CLI pointed at A.
    expect(provisioner).to include('"different-instance"')
    expect(provisioner).to match(/if \(cached\) \{[\s\S]{0,400}different-instance/)
  end

  it "keeps the app window in lockstep with a Preferences URL change (remote mode)" do
    save_credentials = main_process[/const saveCredentials = async[\s\S]*?\n\}/]
    expect(save_credentials).to include('getBackendMode() === "remote"')
    expect(save_credentials).to include('saveBackendConfig({ mode: "remote", serverUrl: normalizedServerUrl })')
  end

  it "persists through main.ts's saveCredentials (validation + cable + 0600 file)" do
    expect(provisioner).not_to include("writeCredentialsFile")
    expect(main_process).to include("maybeProvisionDesktopToken")
  end

  it "triggers on full loads AND in-page navigations — SPA sign-in fires no did-finish-load" do
    expect(main_process).to include('.on("did-finish-load", attemptTokenProvisioning)')
    expect(main_process).to include('.on("did-navigate-in-page", attemptTokenProvisioning)')
    expect(provisioner).to include("attemptInFlight")
  end

  it "only runs against same-origin pages, never the fallback surface" do
    expect(main_process).to include("new URL(handle.window.webContents.getURL()).origin === new URL(serverUrl).origin")
  end
end
