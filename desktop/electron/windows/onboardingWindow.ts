import { BrowserWindow } from "electron"

type OnboardingWindowOptions = {
  preloadPath: string
  loadRenderer: (window: BrowserWindow, view?: string) => Promise<void>
  onClosed: () => void
}

// The first-run window: fixed-size, hiddenInset traffic lights over the
// renderer's own draggable header, macOS-dialog proportions.
export const createOnboardingWindow = async ({ preloadPath, loadRenderer, onClosed }: OnboardingWindowOptions) => {
  const window = new BrowserWindow({
    width: 760,
    height: 540,
    resizable: false,
    fullscreenable: false,
    titleBarStyle: "hiddenInset",
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
