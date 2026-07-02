import { BrowserWindow, shell } from "electron"
import type { WindowBounds } from "../settings.js"

type WebAppWindowOptions = {
  serverUrl: string
  savedBounds: WindowBounds | null
  // Loads the packaged renderer's backend-status view. That page is purely
  // informational — this window carries NO preload (the remote web app must
  // never see the IPC bridge), so recovery is driven by the main process
  // polling /up and calling loadServerUrl() again.
  loadFallback: (window: BrowserWindow) => Promise<void>
  onBoundsChanged: (bounds: WindowBounds) => void
  onLoadFailed: () => void
  onClosed: () => void
}

export type WebAppWindowHandle = {
  window: BrowserWindow
  loadServerUrl: () => Promise<void>
}

export const createWebAppWindow = ({
  serverUrl,
  savedBounds,
  loadFallback,
  onBoundsChanged,
  onLoadFailed,
  onClosed
}: WebAppWindowOptions): WebAppWindowHandle => {
  const serverOrigin = new URL(serverUrl).origin

  const window = new BrowserWindow({
    width: savedBounds?.width ?? 1280,
    height: savedBounds?.height ?? 860,
    x: savedBounds?.x,
    y: savedBounds?.y,
    minWidth: 720,
    minHeight: 480,
    title: "Syrus",
    webPreferences: {
      // The Syrus web app is remote content: full isolation, no bridge.
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true
    }
  })

  // Same-origin navigation stays in the window; everything else (GitHub PRs,
  // issue links, docs) opens in the user's default browser.
  window.webContents.on("will-navigate", (event, targetUrl) => {
    let target: URL
    try {
      target = new URL(targetUrl)
    } catch {
      event.preventDefault()
      return
    }

    if (target.origin !== serverOrigin && target.protocol !== "file:") {
      event.preventDefault()
      if (["http:", "https:"].includes(target.protocol)) {
        void shell.openExternal(target.toString())
      }
    }
  })

  window.webContents.setWindowOpenHandler(({ url }) => {
    try {
      const target = new URL(url)
      if (target.origin === serverOrigin) {
        void window.loadURL(target.toString())
      } else if (["http:", "https:"].includes(target.protocol)) {
        void shell.openExternal(target.toString())
      }
    } catch {
      // Ignore unparseable URLs.
    }

    return { action: "deny" }
  })

  window.webContents.on("did-fail-load", (_event, _errorCode, _description, validatedURL, isMainFrame) => {
    if (!isMainFrame || !validatedURL.startsWith(serverOrigin)) {
      return
    }

    void loadFallback(window).then(onLoadFailed)
  })

  let boundsTimer: NodeJS.Timeout | null = null
  const scheduleBoundsSave = () => {
    if (boundsTimer) {
      clearTimeout(boundsTimer)
    }

    boundsTimer = setTimeout(() => {
      boundsTimer = null
      if (!window.isDestroyed() && !window.isFullScreen()) {
        onBoundsChanged(window.getBounds())
      }
    }, 500)
  }

  window.on("resize", scheduleBoundsSave)
  window.on("move", scheduleBoundsSave)
  window.on("closed", () => {
    if (boundsTimer) {
      clearTimeout(boundsTimer)
      boundsTimer = null
    }

    onClosed()
  })

  return {
    window,
    loadServerUrl: () => window.loadURL(serverUrl)
  }
}
