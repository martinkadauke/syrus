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

  it "sets the quit flag before installing so hide-on-close cannot abort the update" do
    # quitAndInstall closes all windows before any quit event fires; without
    # the flag the tray's hide-on-close handler preventDefaults and the
    # update silently never installs.
    expect(main_process).to match(/isQuitting = true\s*\n\s*appUpdates\.quitAndInstallUpdate\(\)/)
    expect(main_process).to match(/onBeforeQuitForUpdate: \(\) => \{\s*\n\s*isQuitting = true/)
    expect(app_updates).to include('nativeAutoUpdater.on("before-quit-for-update"')
  end

  it "offers the pinned backend upgrade after an app update instead of mutating silently" do
    lifecycle = read(desktop_root, "electron/installer/backendLifecycle.ts")

    # main.ts compares the release manifest pin against the install's .env pin
    # once the backend is up, and asks before applying.
    expect(main_process).to include("offerBackendUpdateIfPinned")
    expect(main_process).to match(/ensureRunning\(\)\.then\(\(\) => offerBackendUpdateIfPinned\(\)\)/)
    expect(main_process).to include("readBackendManifest")
    expect(main_process).to include('"Update Backend"')

    # The update re-runs the bundled installer against the state dir — the
    # same audited pull/up/health path a fresh install takes.
    expect(lifecycle).to match(/currentImagePin[\s\S]*?SYRUS_IMAGE=/)
    expect(lifecycle).to match(/updateBackend[\s\S]*?"--image",\s*\n\s*image/)
    expect(lifecycle).to match(/updateBackend = async[\s\S]*?"--skip-runtime-install"/)
    expect(lifecycle).to include('createWriteStream(path.join(stateDir(), "install.log"), { flags: "a" })')
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

  it "release workflow pins the backend image and never interpolates the tag into shell" do
    # Release builds must stage the versioned image pin (stage-backend-assets
    # only writes it when SYRUS_RELEASE_BUILD=1).
    expect(release_workflow).to match(/SYRUS_RELEASE_BUILD: "1"[\s\S]{0,200}?--publish always/)

    # The tag name is attacker-influenceable; it must reach run: bodies only
    # via env indirection, never ${{ }} inside shell.
    run_bodies = release_workflow.scan(/run: \|[\s\S]*?(?=\n      - |\n\njobs:|\z)/)
    run_bodies.each do |body|
      expect(body).not_to include("${{ steps.version.outputs.version }}")
    end
  end

  it "release workflow enforces version match and the publish-image-first ordering" do
    expect(release_workflow).to include("does not match the tag")
    expect(release_workflow).to include("ghcr.io/v2/tkadauke/syrus-local/manifests")
    expect(release_workflow).to include("bin/publish-image")
  end

  it "release workflow verifies the signature, stapling, and stable DMG aliases" do
    expect(release_workflow).to include("codesign --verify --deep --strict")
    expect(release_workflow).to include("xcrun stapler validate")
    # Both permalinks: Syrus.dmg (Apple Silicon) and Syrus-Intel.dmg (x64).
    expect(release_workflow).to match(%r{cp "desktop/out/Syrus-\$VERSION-arm64\.dmg" "\$RUNNER_TEMP/Syrus\.dmg"})
    expect(release_workflow).to match(%r{cp "desktop/out/Syrus-\$VERSION-x64\.dmg" "\$RUNNER_TEMP/Syrus-Intel\.dmg"})
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
