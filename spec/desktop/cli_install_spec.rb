# frozen_string_literal: true

require "spec_helper"

# The desktop app is the CLI's distribution channel for users without a
# repo clone (docs/cli-desktop-plan.md): per-arch pure-Go binaries staged
# into the bundle, one-click install to ~/.local/bin, credentials written
# from the app's own store so the CLI is signed in on first run.
RSpec.describe "desktop CLI install" do
  let(:desktop_root) { File.expand_path("../../desktop", __dir__) }

  def read(relative_path)
    File.read(File.join(desktop_root, relative_path), encoding: "UTF-8")
  end

  it "stages per-arch CLI binaries and bundles them as extraResources" do
    stage = read("scripts/stage-cli.mjs")
    expect(stage).to include('CGO_ENABLED: "0"')
    expect(stage).to match(/for \(const arch of \["arm64", "amd64"\]\)/)
    # Missing Go must degrade to a notice, not break packaging.
    expect(stage).to include("skipping CLI bundling")

    config = read("electron-builder.yml")
    expect(config).to match(%r{- from: resources/cli\s+to: cli})

    package = JSON.parse(read("package.json"))
    expect(package.dig("scripts", "build")).to include("stage:cli")
  end

  it "installs to ~/.local/bin and needs no login step" do
    main = read("electron/main.ts")
    handler = main[/ipcMain\.handle\("install-syrus-cli"[\s\S]{0,2200}/]
    expect(handler).to include('path.join(os.homedir(), ".local", "bin")')
    # No credentials writing here: credentialsStore.ts owns
    # ~/.syrus/credentials, and the app already keeps it in the CLI-shared
    # format — the CLI is signed in the moment the binary lands.
    expect(handler).not_to include("writeFile")
    expect(handler).to include("const signedIn = cachedCredentials !== null")
    # The availability cache must be re-probed after install.
    expect(handler).to include("cachedCliAvailable = null")
  end

  it "finds and executes the installed CLI even though GUI PATH lacks ~/.local/bin" do
    main = read("electron/main.ts")
    expect(main).to include("const localBinSyrus = ()")
    expect(main).to match(/syrusCliBinary[\s\S]{0,400}localBinSyrus\(\)/)
    # Exec sites must prefer the resolved binary over a bare PATH lookup.
    expect(main).to match(/const cliBinary = \(await syrusCliBinary\(\)\) \?\? "syrus"/)
  end

  it "exposes the install through the bridge" do
    expect(read("electron/preload.cts")).to include('ipcRenderer.invoke("install-syrus-cli")')
    expect(read("src/vite-env.d.ts")).to include("installSyrusCli: () => Promise<SyrusCliInstallResult>")
  end
end
