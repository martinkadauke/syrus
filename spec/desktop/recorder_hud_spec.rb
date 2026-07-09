require "rails_helper"

# The floating recording HUD is a separate always-on-top, DRAGGABLE window so
# the recording controls live OUTSIDE the Syrus web-app window and stay
# reachable while the user demonstrates another app. These pin the wiring: the
# window is created, draggable, forwards Stop/Discard, and is torn down on every
# lifecycle exit so a pill never lingers past a recording.
RSpec.describe "desktop recording HUD" do
  def read(path)
    File.read(Rails.root.join("desktop", path))
  end

  it "creates a frameless, always-on-top, DRAGGABLE HUD window" do
    controller = read("electron/windows/recorderHud.ts")
    expect(controller).to include("new BrowserWindow")
    expect(controller).to include("alwaysOnTop: true")
    expect(controller).to include("movable: true")
    # Shown without stealing focus from the app under test.
    expect(controller).to include("showInactive()")
    # Excluded from the capture — the controls must not pollute the video.
    expect(controller).to include("setContentProtection(true)")
    # A crashed/hung HUD renderer must not leave a stuck always-on-top window.
    expect(controller).to include("render-process-gone")
    expect(controller).to include("unresponsive")

    html = read("assets/recorderHud.html")
    # The pill is a drag region; the buttons are not.
    expect(html).to include("-webkit-app-region: drag")
    expect(html).to include("-webkit-app-region: no-drag")
  end

  it "forwards the HUD's Stop / Discard actions back to the recorder" do
    preload = read("electron/windows/recorderHudPreload.cts")
    expect(preload).to include("recorderHud:action")

    main = read("electron/main.ts")
    expect(main).to include('ipcMain.handle("recorderHud:show"')
    expect(main).to include('ipcMain.handle("recorderHud:update"')
    expect(main).to include('ipcMain.handle("recorderHud:hide"')
    # Button actions are relayed to the web recorder over the shell bridge.
    expect(main).to include('webAppWindow?.window.webContents.send("recorderHud:action", kind)')
  end

  it "tears the HUD down on every lifecycle exit (close, crash, reload, quit)" do
    main = read("electron/main.ts")
    # At least the window-close, render-process-gone, navigation, and quit paths.
    expect(main.scan("recorderHudController?.hide()").size).to be >= 4
  end

  it "exposes the recorderHud bridge on window.syrusShell" do
    preload = read("electron/windows/webAppPreload.cts")
    expect(preload).to include("recorderHud:")
    expect(preload).to include('ipcRenderer.invoke("recorderHud:show"')
  end
end
