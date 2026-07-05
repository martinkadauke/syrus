# frozen_string_literal: true

require "spec_helper"

# The desktop "Connect to your Syrus" flow: URL-only by design (the tray
# token is minted from the signed-in web session; manual token entry lives
# in Preferences for non-admin accounts), bare IPs/hosts accepted with
# http:// and :3000 assumed, and probe failures classified into actionable
# messages instead of a generic "could not connect".
RSpec.describe "desktop connect flow" do
  let(:desktop_root) { File.expand_path("../../desktop", __dir__) }

  def read(relative_path)
    File.read(File.join(desktop_root, relative_path), encoding: "UTF-8")
  end

  it "keeps the two instanceUrl copies byte-identical" do
    # The renderer (live preview) and the main process (authoritative
    # normalization) cannot share a module across tsconfig rootDir
    # boundaries, so the pure analyzer exists twice. They must never drift.
    renderer_copy = read("src/onboarding/instanceUrl.ts")
    driver_copy = read("electron/installer/instanceUrl.ts")
    expect(driver_copy).to eq(renderer_copy)
  end

  it "connects with a URL only — no token crosses the onboarding IPC" do
    expect(read("electron/preload.cts")).to match(/type ConnectRemoteRequest = \{\s*url: string\s*\}/m)
    connect_form = read("src/onboarding/ConnectRemote.tsx")
    # No token input; the design decision is stated in the component.
    expect(connect_form).not_to match(/type="password"/)
    expect(connect_form).to include("deliberately no API-token")
    driver = read("electron/installer/installerDriver.ts")
    expect(driver).to match(/connectRemote\(request: \{ url: string \}\)/)
    expect(driver).not_to include("saveRemoteCredentials")
  end

  it "normalizes bare hosts through the shared analyzer before probing" do
    driver = read("electron/installer/installerDriver.ts")
    expect(driver).to include('import { analyzeInstanceUrl } from "./instanceUrl.js"')
    expect(driver).to match(/const analysis = analyzeInstanceUrl\(request\.url\)/)
  end

  it "classifies probe failures into actionable messages" do
    driver = read("electron/installer/installerDriver.ts")
    expect(driver).to include("Nothing answered at")
    expect(driver).to include("Syrus usually listens on :3000")
    # Rails host authorization is a server-side fix; the error must say so.
    expect(driver).to include("SYRUS_ALLOWED_HOSTS")
    expect(driver).to include("doesn't look like a Syrus instance")
  end

  it "bounds the Preferences credential validation so the form can't hang forever" do
    main = read("electron/main.ts")
    validate = main[/const validateCredentialsWithServer[\s\S]{0,700}/]
    expect(validate).to include("AbortSignal.timeout")
  end
end
