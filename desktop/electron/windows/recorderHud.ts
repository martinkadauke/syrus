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

// The HUD window is sized to its CONTENT: the renderer measures the panel
// after every update (locales differ wildly in hint length) and asks for a
// resize. Clamped so a compromised HUD renderer can't request an absurd
// always-on-top window.
export const HUD_MIN_WIDTH = 120
export const HUD_MAX_WIDTH = 1600
export const HUD_MIN_HEIGHT = 40
export const HUD_MAX_HEIGHT = 240

type Options = {
  // Absolute path to assets/recorderHud.html (resolved by the caller).
  htmlPath: string
  // Absolute path to the compiled recorderHudPreload.cjs.
  preloadPath: string
  // Invoked when the user clicks Stop / Discard / the pen toggle on the HUD.
  onAction: (kind: "stop" | "discard" | "pen") => void
}

export const createRecorderHudController = ({ htmlPath, preloadPath, onAction }: Options): RecorderHudController => {
  let hud: BrowserWindow | null = null
  // False until the first content-fit resize after each show() — see the
  // grow-only rule in the resize handler.
  let sizedSinceShow = false
  const alive = () => hud !== null && !hud.isDestroyed()

  // Forward HUD button clicks to the recorder, but ONLY from our own HUD
  // window's webContents so a stray renderer can't drive Stop/Discard (or arm
  // the pen).
  ipcMain.on("recorderHud:action", (event, kind) => {
    if (!alive() || event.sender !== hud!.webContents) return
    if (kind === "stop" || kind === "discard" || kind === "pen") onAction(kind)
  })

  // Fit the window to the measured panel. Same sender guard as actions. The
  // resize keeps the panel anchored where the user parked it: hold the
  // horizontal CENTER and the BOTTOM edge (it lives above the Dock/taskbar)
  // while the width tracks the content, so a hint change never walks the HUD
  // across the screen.
  ipcMain.on("recorderHud:resize", (event, size) => {
    if (!alive() || event.sender !== hud!.webContents) return
    const requested = (size ?? {}) as { width?: unknown; height?: unknown }
    const width = Math.round(Number(requested.width))
    const height = Math.round(Number(requested.height))
    if (!Number.isFinite(width) || !Number.isFinite(height)) return

    let w = Math.min(Math.max(width, HUD_MIN_WIDTH), HUD_MAX_WIDTH)
    const h = Math.min(Math.max(height, HUD_MIN_HEIGHT), HUD_MAX_HEIGHT)
    // First resize after show() snugs the 480px placeholder to content;
    // afterwards the width only GROWS. Shrinking mid-recording (the hint
    // swaps to the shorter "Drawing" on every pen arm) would shift the
    // buttons under the user's pointer between two clicks.
    if (sizedSinceShow) {
      w = Math.max(w, hud!.getBounds().width)
    }
    sizedSinceShow = true
    const bounds = hud!.getBounds()
    if (bounds.width === w && bounds.height === h) return
    hud!.setBounds({
      x: Math.round(bounds.x + (bounds.width - w) / 2),
      y: Math.round(bounds.y + (bounds.height - h)),
      width: w,
      height: h
    })
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
    sizedSinceShow = false
    if (alive()) {
      update(state)
      hud!.showInactive()
      return
    }

    hud = new BrowserWindow({
      // Placeholder until the renderer measures its panel and requests a
      // content-fitting size over recorderHud:resize.
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
