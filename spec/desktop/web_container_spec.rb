# frozen_string_literal: true

require "spec_helper"

# The main window is a web container over the (local or remote) Syrus web
# app. Remote content must never see the IPC bridge, external links must
# leave the app, and losing the backend swaps in an inert status page that
# recovers automatically.
RSpec.describe "desktop web-container window" do
  let(:desktop_root) { File.expand_path("../../desktop", __dir__) }

  def read(relative_path)
    File.read(File.join(desktop_root, relative_path), encoding: "UTF-8")
  end

  let(:web_app_window) { read("electron/windows/webAppWindow.ts") }
  let(:main_process) { read("electron/main.ts") }
  let(:renderer_entry) { read("src/main.tsx") }
  let(:backend_status) { read("src/BackendStatus.tsx") }

  it "loads remote content fully isolated, with no preload bridge" do
    expect(web_app_window).to include("contextIsolation: true")
    expect(web_app_window).to include("nodeIntegration: false")
    expect(web_app_window).to include("sandbox: true")
    expect(web_app_window).not_to include("preload:")
  end

  it "keeps same-origin navigation in-window and opens everything else externally" do
    expect(web_app_window).to include('window.webContents.on("will-navigate"')
    expect(web_app_window).to include("window.webContents.setWindowOpenHandler")
    expect(web_app_window).to include("target.origin !== serverOrigin")
    expect(web_app_window).to include("shell.openExternal")
  end

  it "falls back to the status page only for main-frame failures of the server URL" do
    expect(web_app_window).to include('"did-fail-load"')
    expect(web_app_window).to include("if (!isMainFrame || !validatedURL.startsWith(serverOrigin))")
  end

  it "recovers by polling /up from the main process and reloading" do
    expect(main_process).to include("startBackendRecoveryPolling")
    expect(main_process).to include("${serverUrl}/up")
    expect(main_process).to include("await webAppWindow?.loadServerUrl()")
  end

  it "keeps the fallback surface inert — no IPC bridge usage" do
    expect(renderer_entry).to include('view === "backend-status"')
    expect(backend_status).not_to include("window.syrusDesktop")
  end

  it "enforces a single running instance that focuses the existing one" do
    expect(main_process).to include("app.requestSingleInstanceLock()")
    expect(main_process).to include('app.on("second-instance"')
  end

  it "offers the move to /Applications before opening any window" do
    when_ready = main_process[/app\.whenReady\(\)\.then\(async \(\) => \{[\s\S]*/]
    expect(when_ready).to include("app.isInApplicationsFolder()")
    expect(when_ready).to include("app.moveToApplicationsFolder()")
    expect(when_ready.index("moveToApplicationsFolder")).to be < when_ready.index("createMenu()")
  end

  it "shows the dock icon only while a real window is open" do
    expect(main_process).to include("const updateDockVisibility = () => {")
    expect(main_process).to include("app.dock?.show()")
    expect(main_process).to include("app.dock?.hide()")
  end

  it "opens the web window (not the browser) from launch, activate, and the tray" do
    expect(main_process).to include("await showWebAppWindow()")
    expect(main_process).to include("void openSyrus()")
    expect(main_process).not_to include("openSyrusInBrowser")
  end

  it "persists and restores the window bounds" do
    expect(main_process).to include('store.get("webAppWindowBounds", null)')
    expect(main_process).to include('store.set("webAppWindowBounds", bounds)')
  end
end
