# frozen_string_literal: true

require "json"
require "yaml"
require "spec_helper"

# Auto-update and the release pipeline. The invariants here are the ones
# that strand users when broken: only signed builds may publish, the zip
# target feeds Squirrel.Mac, and the backend image must exist before the
# tag that pins it.
RSpec.describe "desktop auto-update and release pipeline" do
  let(:repo_root) { File.expand_path("../..", __dir__) }
  let(:desktop_root) { File.join(repo_root, "desktop") }

  def read(*segments)
    File.read(File.join(*segments), encoding: "UTF-8")
  end

  let(:app_updates) { read(desktop_root, "electron/appUpdates.ts") }
  let(:main_process) { read(desktop_root, "electron/main.ts") }
  let(:release_workflow) { read(repo_root, ".github/workflows/release-desktop.yml") }
  let(:ci_workflow) { read(repo_root, ".github/workflows/desktop-ci.yml") }

  it "keeps auto-update inert for unsigned dev builds and test runs" do
    expect(app_updates).to include("app.isPackaged && !process.env.SYRUS_DISABLE_AUTO_UPDATE")
  end

  it "checks on launch and every six hours, logging errors instead of dialoging" do
    expect(app_updates).to include("CHECK_INTERVAL_MS = 6 * 60 * 60 * 1_000")
    expect(app_updates).to match(/autoUpdater\.on\("error"[\s\S]*?console\.warn/)
    expect(app_updates).not_to include("dialog.show")
  end

  it "offers the restart from both the app menu and the tray, plus a manual check" do
    expect(main_process).to include("Restart to update Syrus")
    expect(main_process).to match(/trayContextMenu[\s\S]{0,80}updateMenuItems\(\)/)
    expect(main_process).to include('"Check for Updates…"')
    expect(main_process).to include("appUpdates.initAutoUpdates")
  end

  it "declares the electron-updater dependency" do
    package_json = JSON.parse(read(desktop_root, "package.json"))
    expect(package_json.dig("dependencies", "electron-updater")).not_to be_nil
  end

  it "release workflow parses and only publishes signed tag builds" do
    workflow = YAML.safe_load(release_workflow)
    expect(workflow.dig("permissions", "contents")).to eq("write")
    expect(release_workflow).to include("Refusing to publish an unsigned release")
    expect(release_workflow).to include("--publish always")
    expect(release_workflow).to match(/if: github\.ref_type == 'tag'\s+env:[\s\S]*?run: npm --prefix desktop run build -- --publish always/)
    expect(release_workflow).to include('CSC_IDENTITY_AUTO_DISCOVERY: "false"')
  end

  it "release workflow enforces version match and the publish-image-first ordering" do
    expect(release_workflow).to include("does not match the tag")
    expect(release_workflow).to include("ghcr.io/v2/tkadauke/syrus-local/manifests")
    expect(release_workflow).to include("bin/publish-image")
  end

  it "release workflow verifies the signature, stapling, and stable DMG alias" do
    expect(release_workflow).to include("codesign --verify --deep --strict")
    expect(release_workflow).to include("xcrun stapler validate")
    expect(release_workflow).to include("Syrus.dmg")
  end

  it "desktop CI covers typecheck, builds, and the installer's machine interface" do
    workflow = YAML.safe_load(ci_workflow)
    expect(workflow["jobs"].keys).to include("desktop", "installer")
    expect(ci_workflow).to include("bash -n install.sh")
    expect(ci_workflow).to include("jq -e")
  end

  it "documents the release runbook with the image published before the tag" do
    runbook = read(repo_root, "docs/releasing.md")
    expect(runbook.index("bin/publish-image")).to be < runbook.index("git tag vX.Y.Z")
    expect(runbook).to include("CSC_LINK")
    expect(runbook).to include("must be public")
  end
end
