# frozen_string_literal: true

require "spec_helper"

# The first-run onboarding drives install.sh headlessly. These assertions pin
# the contract between the Electron installer driver and the script's machine
# interface (flags, exit codes, NDJSON events), plus the safety rails around
# the encryption-key guard.
RSpec.describe "desktop onboarding installer" do
  let(:desktop_root) { File.expand_path("../../desktop", __dir__) }

  def read(relative_path)
    File.read(File.join(desktop_root, relative_path), encoding: "UTF-8")
  end

  let(:driver) { read("electron/installer/installerDriver.ts") }
  let(:docker_runtime) { read("electron/installer/dockerRuntime.ts") }
  let(:install_paths) { read("electron/installer/installPaths.ts") }
  let(:onboarding_window) { read("electron/windows/onboardingWindow.ts") }
  let(:main_process) { read("electron/main.ts") }
  let(:preload) { read("electron/preload.cts") }
  let(:renderer_entry) { read("src/main.tsx") }

  it "spawns the bundled install.sh with the headless flag set" do
    expect(driver).to include('spawn("/bin/bash", args, { env: execEnv() })')
    %w[--docker --non-interactive --json --skip-runtime-install --target-dir].each do |flag|
      expect(driver).to include(%("#{flag}"))
    end
  end

  it "augments PATH for GUI-spawned docker invocations" do
    expect(docker_runtime).to include('".orbstack", "bin"')
    expect(docker_runtime).to include("/Applications/Docker.app/Contents/Resources/bin")
    expect(driver).to include("execEnv()")
  end

  it "resolves bundled assets from the sealed Resources dir when packaged" do
    expect(install_paths).to include('path.join(process.resourcesPath, "backend")')
    expect(install_paths).to include("manifest.json")
  end

  it "maps installer exit codes onto recovery states" do
    expect(driver).to include("if (code === 10 || code === 11)")
    expect(driver).to include("if (code === 20)")
    expect(driver).to match(/code === 20.*adoptExisting/m)
    expect(driver).to include('"local.failed"')
  end

  it "persists the backend config only on a successful install" do
    expect(driver).to match(/code === 0[\s\S]*?saveBackendConfig\(\{\s*mode: "local"/)
  end

  it "cancels a running install with SIGTERM and returns to welcome" do
    expect(driver).to include('this.child.kill("SIGTERM")')
    expect(driver).to match(/cancelRequested[\s\S]*?\{ phase: "welcome" \}/)
  end

  it "adopts an existing install by copying the original .env, never moving it" do
    expect(driver).to include("fs.copyFile(")
    expect(driver).not_to include("fs.rename(")
    expect(driver).to include('"showHiddenFiles"')
  end

  it "guides runtime acquisition through OrbStack without Homebrew" do
    expect(driver).to include("https://orbstack.dev/download")
    expect(driver).not_to include("brew ")
  end

  it "uses a fixed-size hiddenInset onboarding window" do
    expect(onboarding_window).to include('titleBarStyle: "hiddenInset"')
    expect(onboarding_window).to include("width: 760")
    expect(onboarding_window).to include("resizable: false")
  end

  it "opens onboarding on startup until a backend mode is configured" do
    expect(main_process).to include('if (getBackendMode() === "") {')
    expect(main_process).to include("await showOnboardingWindow()")
  end

  it "registers the onboarding IPC surface and pushes state changes" do
    %w[
      onboarding:get-state onboarding:choose-mode onboarding:connect-remote
      onboarding:start-install onboarding:cancel-install onboarding:retry
      onboarding:locate-env onboarding:wipe-data onboarding:open-orbstack-download
    ].each do |channel|
      expect(main_process).to include(%("#{channel}"))
    end
    expect(main_process).to include('"onboarding:state-changed"')
    expect(preload).to include("onOnboardingState")
    expect(preload).to include("getOnboardingState")
  end

  it "routes the onboarding view to its own renderer surface" do
    expect(renderer_entry).to include('view === "onboarding"')
    expect(renderer_entry).to include("<OnboardingApp />")
  end

  it "gates the destructive wipe behind a typed confirmation in the renderer" do
    adopt_existing = read("src/onboarding/AdoptExisting.tsx")
    expect(adopt_existing).to include('=== "delete"')
    expect(adopt_existing).to include("disabled={!wipeArmed}")
    expect(driver).to match(/wipeData[\s\S]*?showMessageBox/)
  end
end
