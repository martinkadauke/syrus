import { app } from "electron"
import electronUpdater from "electron-updater"

const { autoUpdater } = electronUpdater

const CHECK_INTERVAL_MS = 6 * 60 * 60 * 1_000

// Auto-update rides the GitHub Releases feed baked in by electron-builder's
// publish config (latest-mac.yml + zip). macOS updates only install into a
// signed app — Squirrel.Mac validates the signature — so everything here is
// inert for unsigned dev builds (!app.isPackaged) and can be switched off
// with SYRUS_DISABLE_AUTO_UPDATE (CI, tests).
const updatesEnabled = () => app.isPackaged && !process.env.SYRUS_DISABLE_AUTO_UPDATE

let downloadedVersion: string | null = null
let checkTimer: NodeJS.Timeout | null = null

type UpdateDeps = {
  // main.ts re-renders the app menu and tray menu with a
  // "Restart to update Syrus (vX)" item.
  onUpdateDownloaded: (version: string) => void
}

export const initAutoUpdates = (deps: UpdateDeps) => {
  if (!updatesEnabled() || checkTimer) {
    return
  }

  autoUpdater.autoDownload = true

  autoUpdater.on("update-downloaded", (info) => {
    downloadedVersion = info.version
    deps.onUpdateDownloaded(info.version)
  })

  // Log-only: a tray app that dialogs about failed update checks would spam
  // every offline user.
  autoUpdater.on("error", (error) => {
    console.warn("[auto-update]", error instanceof Error ? error.message : error)
  })

  void autoUpdater.checkForUpdates().catch(() => {})
  checkTimer = setInterval(() => {
    void autoUpdater.checkForUpdates().catch(() => {})
  }, CHECK_INTERVAL_MS)
}

export const downloadedUpdateVersion = () => downloadedVersion

// The existing before-quit handler sets isQuitting, so windows close for
// real instead of hiding — quitAndInstall composes with the tray lifecycle.
export const quitAndInstallUpdate = () => {
  autoUpdater.quitAndInstall()
}

export type InteractiveCheckResult =
  | { outcome: "disabled" }
  | { outcome: "downloaded"; version: string }
  | { outcome: "downloading"; version: string }
  | { outcome: "up-to-date"; version: string }
  | { outcome: "error" }

export const checkForUpdatesInteractive = async (): Promise<InteractiveCheckResult> => {
  if (!updatesEnabled()) {
    return { outcome: "disabled" }
  }

  if (downloadedVersion) {
    return { outcome: "downloaded", version: downloadedVersion }
  }

  try {
    const result = await autoUpdater.checkForUpdates()
    const available = result?.updateInfo?.version
    if (available && available !== app.getVersion()) {
      return { outcome: "downloading", version: available }
    }

    return { outcome: "up-to-date", version: app.getVersion() }
  } catch {
    return { outcome: "error" }
  }
}
