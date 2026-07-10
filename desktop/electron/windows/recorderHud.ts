import { BrowserWindow, ipcMain, screen } from "electron"

// The floating recording HUD: a small always-on-top, DRAGGABLE window carrying
// the recording controls (elapsed clock, remaining countdown, mic warning,
// draw-mode hint, Stop, Discard). It lives OUTSIDE the Syrus web-app window so
// the user can park it anywhere on screen — including off the surface they're
// demonstrating — and still reach Stop/Discard without switching back to Syrus.
// The web recorder pushes state via update(); the HUD's buttons send actions
// back through the onAction callback. See assets/recorderHud.html +
// recorderHudPreload.cts.

// A loose bag pushed to the HUD renderer verbatim (clock, remaining, hint, …).
export type RecorderHudState = Record<string, unknown>

export type RecorderHudController = {
  show: (state: RecorderHudState) => void
  update: (state: RecorderHudState) => void
  hide: () => void
  isVisible: () => boolean
}

type Options = {
  // Absolute path to assets/recorderHud.html (resolved by the caller).
  htmlPath: string
  // Absolute path to the compiled recorderHudPreload.cjs.
  preloadPath: string
  // Invoked when the user clicks Stop / Discard on the HUD.
  onAction: (kind: "stop" | "discard") => void
}

export const createRecorderHudController = ({ htmlPath, preloadPath, onAction }: Options): RecorderHudController => {
  let hud: BrowserWindow | null = null
  const alive = () => hud !== null && !hud.isDestroyed()

  // Forward HUD button clicks to the recorder, but ONLY from our own HUD
  // window's webContents so a stray renderer can't drive Stop/Discard.
  ipcMain.on("recorderHud:action", (event, kind) => {
    if (!alive() || event.sender !== hud!.webContents) return
    if (kind === "stop" || kind === "discard") onAction(kind)
  })

  // Park the pill at the bottom-center of the display the cursor is on, above
  // the Dock/taskbar. The user can drag it from there.
  const positionInitially = (win: BrowserWindow) => {
    try {
      const area = screen.getDisplayNearestPoint(screen.getCursorScreenPoint()).workArea
      const [w, h] = win.getSize()
      win.setPosition(Math.round(area.x + (area.width - w) / 2), Math.round(area.y + area.height - h - 24))
    } catch {
      // multi-monitor / headless quirk — leave the default position
    }
  }

  const update = (state: RecorderHudState) => {
    if (!alive()) return
    hud!.webContents.send("recorderHud:update", state)
  }

  const show = (state: RecorderHudState) => {
    if (alive()) {
      update(state)
      hud!.showInactive()
      return
    }

    hud = new BrowserWindow({
      width: 480,
      height: 88,
      frame: false,
      transparent: true,
      hasShadow: false,
      resizable: false,
      // Draggable — the whole point. movable + the html's -webkit-app-region.
      movable: true,
      minimizable: false,
      maximizable: false,
      fullscreenable: false,
      skipTaskbar: true,
      // Shown without activating so arming it at record start never steals
      // focus from the app under test; clicking a button focuses it as needed.
      show: false,
      alwaysOnTop: true,
      webPreferences: {
        contextIsolation: true,
        nodeIntegration: false,
        sandbox: true,
        preload: preloadPath
      }
    })

    hud.setAlwaysOnTop(true, "screen-saver")
    hud.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true })
    // Exclude the HUD from the screen capture (unlike the annotation overlay,
    // which MUST be captured): the recording controls should never pollute the
    // walkthrough video or the OCR screenshots. macOS ScreenCaptureKit /
    // Windows SetWindowDisplayAffinity honor this; it's a no-op elsewhere.
    hud.setContentProtection(true)
    hud.on("closed", () => { hud = null })
    // If the HUD renderer crashes or hangs, tear the window down — an
    // always-on-top, content-protected window stuck on screen (that the user
    // can't even screen-record to show us) is the worst failure here.
    hud.webContents.on("render-process-gone", () => hide())
    hud.webContents.on("unresponsive", () => hide())

    // Push the initial state only AFTER the page (and its onUpdate listener)
    // has loaded, or the first send is dropped.
    void hud.loadFile(htmlPath).then(() => update(state)).catch(() => {})
    positionInitially(hud)
    hud.showInactive()
  }

  const hide = () => {
    if (!alive()) return
    hud!.destroy()
    hud = null
  }

  return { show, update, hide, isVisible: alive }
}
