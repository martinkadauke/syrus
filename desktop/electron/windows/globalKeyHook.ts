import { createRequire } from "module"
import { systemPreferences } from "electron"

// True hold-to-draw needs a GLOBAL keyboard hook — the annotation overlay only
// has focus while armed, so it can't see the modifier key while the user is
// interacting with the app under test. uiohook-napi provides that hook. It's an
// N-API module (ABI-stable across Node/Electron — no electron-rebuild) with
// prebuilt binaries for every platform+arch we ship, but it's still native, so
// EVERY entry point here fails soft: a load error, a start error, or (on macOS)
// missing Accessibility permission returns null, and the caller falls back to
// the no-native tap-to-arm shortcut. The app must never break because the hook
// couldn't run.

const require = createRequire(import.meta.url)

type UiohookModule = {
  uIOhook: {
    on: (event: string, callback: (event: { keycode: number }) => void) => void
    start: () => void
    stop: () => void
    removeAllListeners: () => void
  }
  UiohookKey: Record<string, number>
}

// undefined = not attempted; null = attempted and failed (missing prebuild,
// load error). Cached so a failed load is tried at most once.
let cachedModule: UiohookModule | null | undefined
let promptedAccessibility = false

const loadUiohook = (): UiohookModule | null => {
  if (cachedModule !== undefined) return cachedModule
  try {
    cachedModule = require("uiohook-napi") as UiohookModule
  } catch {
    cachedModule = null
  }
  return cachedModule
}

// macOS gates global key capture behind Accessibility permission; without it
// uIOhook.start() succeeds but no events arrive. Check silently, and prompt at
// most ONCE per app run (opening System Settings) so a user who declines isn't
// nagged on every recording — they just get the tap-to-arm fallback. Windows /
// Linux need no special permission.
const accessibilityReady = (): boolean => {
  if (process.platform !== "darwin") return true
  if (systemPreferences.isTrustedAccessibilityClient(false)) return true
  if (!promptedAccessibility) {
    promptedAccessibility = true
    systemPreferences.isTrustedAccessibilityClient(true)
  }
  return false
}

export type HoldToDrawHook = { stop: () => void }

// Start a global hook that fires onHold when a Ctrl key goes DOWN and onRelease
// when the last held Ctrl goes UP. Returns null when the native hook can't run
// (module missing, load/start error, or macOS Accessibility not granted) — the
// caller then falls back to the tap-to-arm shortcut.
export const startHoldToDrawHook = ({
  onHold,
  onRelease
}: {
  onHold: () => void
  onRelease: () => void
}): HoldToDrawHook | null => {
  if (!accessibilityReady()) return null

  const module = loadUiohook()
  if (!module) return null

  const { uIOhook, UiohookKey } = module
  const ctrlCodes = new Set([UiohookKey.Ctrl, UiohookKey.CtrlRight].filter((code) => typeof code === "number"))
  if (ctrlCodes.size === 0) return null

  let held = false
  const onKeyDown = (event: { keycode: number }) => {
    if (ctrlCodes.has(event.keycode) && !held) {
      held = true
      onHold()
    }
  }
  const onKeyUp = (event: { keycode: number }) => {
    if (ctrlCodes.has(event.keycode) && held) {
      held = false
      onRelease()
    }
  }

  try {
    uIOhook.on("keydown", onKeyDown)
    uIOhook.on("keyup", onKeyUp)
    uIOhook.start()
  } catch {
    try {
      uIOhook.removeAllListeners()
      uIOhook.stop()
    } catch {
      // never started — nothing to unwind
    }
    return null
  }

  return {
    stop: () => {
      try {
        uIOhook.removeAllListeners()
        uIOhook.stop()
      } catch {
        // already stopped
      }
    }
  }
}
