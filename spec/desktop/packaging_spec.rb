# frozen_string_literal: true

require "json"
require "spec_helper"

# Distribution config: the DMG a user downloads must be signable, notarizable,
# and auto-updatable. These assertions pin the load-bearing electron-builder
# settings and the backend-asset staging contract.
RSpec.describe "desktop packaging" do
  let(:desktop_root) { File.expand_path("../../desktop", __dir__) }

  def read(relative_path)
    File.read(File.join(desktop_root, relative_path), encoding: "UTF-8")
  end

  let(:builder_config) { read("electron-builder.yml") }
  let(:package_json) { JSON.parse(read("package.json")) }
  let(:staging_script) { read("scripts/stage-backend-assets.mjs") }

  it "moves the build config out of package.json into electron-builder.yml" do
    expect(package_json).not_to have_key("build")
    expect(builder_config).to include("appId: app.syrus.desktop")
  end

  it "ships as Syrus.app, mirroring Claude Desktop naming" do
    expect(builder_config).to include("productName: Syrus\n")
  end

  it "configures Gatekeeper-clean signing: hardened runtime, entitlements, notarization" do
    expect(builder_config).to include("hardenedRuntime: true")
    expect(builder_config).to include("entitlements: build/entitlements.mac.plist")
    expect(builder_config).to include("notarize: true")
    expect(File).to exist(File.join(desktop_root, "build/entitlements.mac.plist"))
  end

  it "keeps entitlements minimal — no library-validation opt-out" do
    entitlements = read("build/entitlements.mac.plist")
    expect(entitlements).to include("com.apple.security.cs.allow-jit")
    expect(entitlements).not_to include("<key>com.apple.security.cs.disable-library-validation</key>")
  end

  it "builds the zip target auto-update requires alongside the dmg" do
    expect(builder_config).to match(/- target: dmg\s+arch:/)
    expect(builder_config).to match(/- target: zip\s+arch:/)
  end

  it "lays the DMG out as drag-to-Applications" do
    expect(builder_config).to include("type: link")
    expect(builder_config).to include("path: /Applications")
  end

  it "publishes to the tkadauke/syrus GitHub feed the shipped apps will read" do
    expect(builder_config).to match(/provider: github\s+owner: tkadauke\s+repo: syrus/)
  end

  it "bundles the backend installer assets as sealed extraResources" do
    expect(builder_config).to match(/extraResources:\s+- from: resources\/backend\s+to: backend/)
    expect(package_json.dig("scripts", "build")).to include("stage:backend")
  end

  it "stages install.sh, compose file, env template, and a version-pinned manifest" do
    %w[install.sh docker-compose.yml compose.env.example].each do |asset|
      expect(staging_script).to include(%("#{asset}"))
    end
    expect(staging_script).to include("ghcr.io/tkadauke/syrus-local:${version}")
    expect(staging_script).to include('ghcr.io/tkadauke/syrus-local:latest')
    expect(staging_script).to include("manifest.json")
  end

  it "keeps staged resources out of git" do
    gitignore = File.read(File.expand_path("../../.gitignore", __dir__), encoding: "UTF-8")
    expect(gitignore).to include("desktop/resources/")
  end
end
