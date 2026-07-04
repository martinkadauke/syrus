# frozen_string_literal: true

require "spec_helper"

# Phase 1 of the Windows port (docs/windows-desktop-plan.md): packaging,
# platform seams, and runtime guidance exist; the local-install path is
# explicitly guarded until the PowerShell installer lands. These specs pin
# the seams so mac-only assumptions don't creep back in.
RSpec.describe "desktop Windows scaffold" do
  let(:desktop_root) { File.expand_path("../../desktop", __dir__) }
  let(:repo_root) { File.expand_path("../..", __dir__) }

  def read(relative_path)
    File.read(File.join(desktop_root, relative_path), encoding: "UTF-8")
  end

  it "documents the plan the scaffold implements" do
    plan = File.read(File.join(repo_root, "docs/windows-desktop-plan.md"), encoding: "UTF-8")
    expect(plan).to include("NSIS one-click")
    expect(plan).to include("Podman Desktop")
    expect(plan).to include("UTM")
  end

  it "packages a per-user NSIS one-click installer with the brand .ico for x64 and arm64" do
    config = read("electron-builder.yml")
    expect(config).to include("icon: build/icon.ico")
    expect(config).to match(/win:[\s\S]{0,400}- target: nsis\s+arch: \[x64, arm64\]/)
    expect(config).to match(/nsis:\s+oneClick: true\s+perMachine: false/)
    expect(File).to exist(File.join(desktop_root, "build/icon.ico"))
    expect(File).to exist(File.join(desktop_root, "scripts/make-ico.mjs"))
    # electron-updater cannot auto-update MSI installs; NSIS is the canonical
    # Windows artifact (see the plan doc) — no msi target without a decision.
    expect(config).not_to include("msi")
  end

  it "keeps the macOS-only titleBarStyle off other platforms" do
    onboarding_window = read("electron/windows/onboardingWindow.ts")
    expect(onboarding_window).to match(/process\.platform === "darwin" \? \{ titleBarStyle: "hiddenInset"/)
  end

  it "detects Windows Docker runtimes and recommends Docker Desktop with Podman Desktop as the alternative" do
    runtime = read("electron/installer/dockerRuntime.ts")
    expect(runtime).to include('process.platform === "win32"')
    expect(runtime).to include("docker.exe")
    expect(runtime).to include("Podman Desktop")
    expect(runtime).to include("https://podman-desktop.io/downloads")
    expect(runtime).to include("path.delimiter")
  end

  it "guards the bash-driven local install on Windows instead of dying on /bin/bash" do
    driver = read("electron/installer/installerDriver.ts")
    guard = driver[/async startInstall\(portOverride\?: number\) \{[\s\S]{0,900}/]
    expect(guard).to include('process.platform === "win32"')
    expect(guard).to include("connect to an existing Syrus instance")
  end

  it "exposes the platform to the renderer so onboarding can adapt" do
    expect(read("electron/preload.cts")).to include("platform: process.platform")
    expect(read("src/vite-env.d.ts")).to include("platform: string")
    welcome = read("src/onboarding/Welcome.tsx")
    expect(welcome).to include('platform !== "win32"')
  end
end
