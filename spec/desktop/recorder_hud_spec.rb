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

  it "renders a RECTANGULAR panel (rounded corners artifact on transparent windows)" do
    html = read("assets/recorderHud.html")
    # The panel itself must not be rounded — the transparent always-on-top
    # window composites rounded corners with visible artifacts on macOS, and
    # the rectangle matches the web app's bordered-white-panel look. (The
    # recording dot / pen dot stay circles; buttons keep a small 4px radius.)
    pill = html[/\.pill \{[\s\S]*?\}/]
    expect(pill).not_to include("border-radius")
    expect(pill).to include("border: 1px solid")
    expect(html).not_to include("border-radius: 9999px;\n        background")
  end

  it "sizes the WINDOW to the panel so no locale's hint is ever truncated" do
    html = read("assets/recorderHud.html")
    # The renderer measures the panel after every render and reports it...
    expect(html).to include("pill.offsetWidth")
    expect(html).to include("__recorderHud.resize")

    # ...through a dedicated preload channel (send, not invoke — the parity
    # spec scans only the invoke-based bridges in preload.cts/webAppPreload.cts)...
    preload = read("electron/windows/recorderHudPreload.cts")
    expect(preload).to include('ipcRenderer.send("recorderHud:resize", size)')

    # ...and main applies it with the SAME sender guard as actions, clamped,
    # anchored to the panel's center/bottom so it never walks while dragging.
    controller = read("electron/windows/recorderHud.ts")
    resize = controller[/ipcMain\.on\("recorderHud:resize"[\s\S]{0,1200}/]
    expect(resize).to include("event.sender !== hud!.webContents")
    expect(resize).to include("Number.isFinite(width)")
    expect(resize).to match(/Math\.min\(Math\.max\(width, HUD_MIN_WIDTH\), HUD_MAX_WIDTH\)/)
    expect(resize).to include("hud!.setBounds({")
    expect(resize).to include("bounds.x + (bounds.width - w) / 2")
    # After the first content-fit of each show(), the width only grows —
    # shrinking mid-recording would shift the buttons under the pointer.
    expect(resize).to match(/if \(sizedSinceShow\) \{[\s\S]{0,120}Math\.max\(w, hud!\.getBounds\(\)\.width\)/)
    expect(controller).to include("sizedSinceShow = false")

    html = read("assets/recorderHud.html")
    # The pen button's accessible name is pushed localized like every other
    # HUD string; the hardcoded text is only the fallback.
    expect(html).to include('$("pen").setAttribute("aria-label", current.penLabel || "Toggle drawing")')
    expect(resize).to include("bounds.y + (bounds.height - h)")
  end

  it "renders the hold indicator as a QUIET dot + short text, not shouting red" do
    html = read("assets/recorderHud.html")
    # A tiny neutral dot next to muted 11px text while idle; the dot (only)
    # turns red while drawing. The old 600-weight red hint is gone.
    expect(html).to include('id="penstatus"')
    expect(html).to include('class="pendot"')
    expect(html).to include(".penstatus.drawing .pendot { background: #dc2626; }")
    expect(html).not_to include(".hint { font-size: 12px; color: #dc2626; font-weight: 600; }")
  end

  it "plumbs the mouse-only pen toggle end-to-end (button -> preload -> filter -> overlay)" do
    # The zero-keyboard fallback: works regardless of uiohook or macOS
    # Accessibility, because main flips the overlay's pointer capture directly.
    html = read("assets/recorderHud.html")
    pen_button = html[/<button class="pen[^>]*>/]
    expect(pen_button).to include('aria-label="Toggle drawing"')
    expect(pen_button).to include('aria-pressed="false"')
    expect(html).to include('window.__recorderHud.action("pen")')
    # Pressed/active state driven by the drawing flag pushed over update.
    expect(html).to include('$("pen").classList.add("active")')
    expect(html).to match(/\$\("pen"\)\.setAttribute\("aria-pressed", current\.drawing \? "true" : "false"\)/)

    preload = read("electron/windows/recorderHudPreload.cts")
    expect(preload).to include('action: (kind: "stop" | "discard" | "pen")')

    controller = read("electron/windows/recorderHud.ts")
    expect(controller).to include('kind === "stop" || kind === "discard" || kind === "pen"')

    # main INTERCEPTS pen (drives the overlay), forwards everything else.
    main = read("electron/main.ts")
    on_action = main[/const ensureRecorderHud[\s\S]{0,1200}/]
    expect(on_action).to match(/if \(kind === "pen"\) \{[\s\S]{0,80}annotationController\?\.toggleDraw\(\)[\s\S]{0,40}return/)

    # The overlay's toggleDraw arms through the same setArmed path, and a
    # pen-armed session always gets the auto-release watchers (even in hold
    # mode) so a mouse-only user can never get stuck armed.
    overlay = read("electron/windows/annotationOverlay.ts")
    toggle_draw = overlay[/const toggleDraw[\s\S]{0,400}/]
    expect(toggle_draw).to include("setArmed(next)")
    expect(toggle_draw).to match(/mode === "hold"[\s\S]{0,40}startArmWatch\(\)/)
    expect(overlay).to include("toggleDraw")
  end

  it "pushes draw-mode transitions straight to the HUD so the pen state flips instantly" do
    main = read("electron/main.ts")
    mode_changed = main[/onModeChanged: \(drawing\) => \{[\s\S]{0,300}/]
    expect(mode_changed).to include('webAppWindow?.window.webContents.send("annotation:mode-changed", drawing)')
    expect(mode_changed).to include("recorderHudController?.update({ drawing })")

    # A partial update ({ drawing }) must MERGE into the HUD's last-known
    # state, not blank the clock/hint — the renderer keeps a merged bag.
    html = read("assets/recorderHud.html")
    expect(html).to match(/for \(var key in state\)[\s\S]{0,120}current\[key\] = state\[key\]/)
  end
end
