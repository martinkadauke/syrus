import { BrowserWindow } from "electron"

type OnboardingWindowOptions = {
  preloadPath: string
  loadRenderer: (window: BrowserWindow, view?: string) => Promise<void>
  onClosed: () => void
}

// The first-run window: fixed-size, macOS-dialog proportions. hiddenInset
// (traffic lights floating over the renderer's draggable header) is a
// macOS-only titleBarStyle — Windows/Linux keep the native frame.
export const createOnboardingWindow = async ({ preloadPath, loadRenderer, onClosed }: OnboardingWindowOptions) => {
  const window = new BrowserWindow({
    width: 760,
    height: 540,
    resizable: false,
    fullscreenable: false,
    ...(process.platform === "darwin" ? { titleBarStyle: "hiddenInset" as const } : {}),
    title: "Welcome to Syrus",
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      preload: preloadPath
    }
  })

  window.on("closed", onClosed)
  await loadRenderer(window, "onboarding")
  return window
}
