import { createRequire } from "module"
import fs from "fs"
import path from "path"
import { app, systemPreferences } from "electron"

// True hold-to-draw needs a GLOBAL keyboard hook — the annotation overlay only
// has focus while armed, so it can't see the modifier key while the user is
// interacting with the app under test. uiohook-napi provides that hook. It's an
// N-API module (ABI-stable across Node/Electron — no electron-rebuild) with
// prebuilt binaries for every platform+arch we ship, but it's still native, so
// EVERY entry point here fails soft: a load error, a start error, or (on macOS)
// missing Accessibility permission returns a null hook, and the caller falls
// back to the no-native tap-to-arm shortcut. The app must never break because
// the hook couldn't run.
//
// Failing soft is NOT the same as failing silently: every failure point logs
// WHY (console + a small append-only file under userData) and reports a
// machine-readable `reason`, so "I held Ctrl and nothing happened" is
// diagnosable from a user's machine and the HUD can tell the user how to get
// hold mode back (grant Accessibility) instead of shrugging.

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

// Why the hold hook could not start. Threaded through enable() → IPC → the web
// recorder so the HUD hint can name the actual obstacle (and, for
// no-accessibility, tell the user granting the permission fixes it).
export type HoldHookFailureReason = "no-module" | "no-accessibility" | "start-failed"

// Diagnostic trail for hold-to-draw failures. console.warn for dev/terminal
// runs, PLUS an append-only line in <userData>/hold-to-draw.log because a
// packaged DMG has no visible console — the log file is the only way to see
// why hold mode degraded on a user's machine. Logging must never throw: a
// diagnostics failure must not take down the feature it diagnoses.
export const HOLD_TO_DRAW_LOG_BASENAME = "hold-to-draw.log"

const logHoldToDrawFailure = (message: string, error?: unknown) => {
  const detail = error instanceof Error ? error.message : error ? String(error) : ""
  const line = `[hold-to-draw] ${message}${detail ? ` — ${detail}` : ""}`
  try {
    console.warn(line)
  } catch {
    // even console can be broken mid-teardown — never throw from logging
  }
  try {
    fs.appendFileSync(path.join(app.getPath("userData"), HOLD_TO_DRAW_LOG_BASENAME), `${new Date().toISOString()} ${line}\n`)
  } catch {
    // unwritable userData (or app not ready) — the console line has to do
  }
}

// Cache ONLY a successful load. A failed require must NOT be cached: the old
// null-forever cache turned any transient load failure into a permanent
// degrade to tap mode for the whole process — a retry on the next enable()
// costs microseconds and self-heals.
let cachedModule: UiohookModule | null = null

const loadUiohook = (): UiohookModule | null => {
  if (cachedModule) return cachedModule
  try {
    cachedModule = require("uiohook-napi") as UiohookModule
    return cachedModule
  } catch (error) {
    logHoldToDrawFailure("uiohook-napi failed to load (will retry on next enable)", error)
    return null
  }
}

// macOS gates global key capture behind Accessibility permission; without it
// uIOhook.start() succeeds but no events arrive. Check silently, and prompt at
// most ONCE per gate window (opening System Settings) so a user who declines
// isn't nagged on every re-check — they just get the tap-to-arm fallback.
// Windows / Linux need no special permission.
let promptedAccessibility = false

// Re-open the prompt gate. Called when the annotation overlay is disabled
// (recording over) so each RECORDING re-checks the permission: a user who
// grants Accessibility mid-session gets hold mode on their NEXT recording
// without relaunching the app, while still seeing at most one OS prompt per
// recording.
export const resetAccessibilityPromptGate = () => {
  promptedAccessibility = false
}

const accessibilityReady = (): boolean => {
  if (process.platform !== "darwin") return true
  if (systemPreferences.isTrustedAccessibilityClient(false)) return true
  if (!promptedAccessibility) {
    promptedAccessibility = true
    systemPreferences.isTrustedAccessibilityClient(true)
  }
  logHoldToDrawFailure("macOS Accessibility permission not granted — falling back to tap-to-arm")
  return false
}

export type HoldToDrawHook = { stop: () => void }

// What startHoldToDrawHook reports: the live hook, or null plus WHY it
// couldn't run so callers can surface the obstacle instead of a silent
// degrade.
export type HoldToDrawStart = { hook: HoldToDrawHook | null; reason?: HoldHookFailureReason }

// Start a global hook that fires onHold when a Ctrl key goes DOWN and onRelease
// when the last held Ctrl goes UP. Reports a null hook (plus a reason) when the
// native hook can't run (module missing, load/start error, or macOS
// Accessibility not granted) — the caller then falls back to the tap-to-arm
// shortcut.
export const startHoldToDrawHook = ({
  onHold,
  onRelease
}: {
  onHold: () => void
  onRelease: () => void
}): HoldToDrawStart => {
  if (!accessibilityReady()) return { hook: null, reason: "no-accessibility" }

  const module = loadUiohook()
  if (!module) return { hook: null, reason: "no-module" }

  const { uIOhook, UiohookKey } = module
  const ctrlCodes = new Set([UiohookKey.Ctrl, UiohookKey.CtrlRight].filter((code) => typeof code === "number"))
  if (ctrlCodes.size === 0) {
    logHoldToDrawFailure("uiohook-napi loaded but exposes no Ctrl keycodes — treating as unusable module")
    return { hook: null, reason: "no-module" }
  }

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
  } catch (error) {
    logHoldToDrawFailure("uIOhook.start() failed — falling back to tap-to-arm", error)
    try {
      uIOhook.removeAllListeners()
      uIOhook.stop()
    } catch (stopError) {
      // KNOWN uiohook quirk: a failed stop() can leave its internal
      // is_worker_running flag set, after which a later start() silently
      // no-ops — the one case where a hook "starts" but Ctrl does nothing.
      // Log it so that state is visible instead of mystifying.
      logHoldToDrawFailure("uIOhook.stop() failed during start-failure unwind (later starts may silently no-op)", stopError)
    }
    return { hook: null, reason: "start-failed" }
  }

  return {
    hook: {
      stop: () => {
        try {
          uIOhook.removeAllListeners()
          uIOhook.stop()
        } catch (error) {
          // Same quirk as above: a failed stop() can wedge uiohook's internal
          // worker flag and make the NEXT start() a silent no-op. Log it.
          logHoldToDrawFailure("uIOhook.stop() failed (next hold-to-draw start may silently no-op)", error)
        }
      }
    }
  }
}
