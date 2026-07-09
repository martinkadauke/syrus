import { BrowserWindow, globalShortcut, screen } from "electron"
import { startHoldToDrawHook, type HoldToDrawHook } from "./globalKeyHook.js"

// Red-pen screen annotation during a walkthrough recording. The overlay is a
// frameless, transparent, always-on-top window spanning EVERY display; the
// walkthrough recorder's full-screen getDisplayMedia captures it INCIDENTALLY,
// so marks the user draws are burned into the recorded video with no change to
// the capture pipeline. See assets/annotationOverlay.html for the canvas + fade
// renderer.
//
// Interaction model — HOLD-TO-DRAW, with a tap-to-arm fallback:
//
// - HOLD mode (preferred): a global keyboard hook (globalKeyHook.ts /
//   uiohook-napi) arms draw mode while a Ctrl key is physically DOWN and
//   releases it the instant the key comes UP. The pen is live only while held —
//   exactly the model the operator asked for — and needs no auto-release timers.
//   The global hook needs macOS Accessibility permission; when that (or the
//   native module) is unavailable, enable() FALLS BACK to:
//
// - TAP mode: tapping the global shortcut (CommandOrControl+Shift+A) ARMS draw
//   mode; it AUTO-RELEASES after the pointer goes idle for ARM_IDLE_RELEASE_MS,
//   with a hard MAX_ARMED_MS cap so it can never get stuck capturing the screen.
//   Zero native code, zero permission prompts — always available.
//
// enable() reports which mode came up ({ available, hold }) so the recorder HUD
// shows the right hint ("Hold Ⓒ to draw" vs "tap ⌘⇧A"). Esc releases immediately
// in either mode.
//
// Focus discipline (never steal the narrator's keystrokes): the overlay is
// created NON-ACTIVATING (focusable:false, shown with showInactive) so arming
// it at record start never moves focus off the app under test. Focus is granted
// ONLY while armed — the canvas needs pointer input and the Escape key — and
// dropped again the instant draw mode releases. enable() itself never moves
// focus.
//
// Multi-display: the overlay spans the UNION of every display's bounds, so
// drawing appears on whichever monitor the recorder is sharing, not just the
// primary. A single union-spanning window (rather than one window per display)
// keeps the canvas coordinate space contiguous and is the most portable option
// across macOS/Windows/Linux compositors. Caveat: on macOS a non-contiguous
// display arrangement can leave the window clamped to the display holding its
// origin; the common adjacent arrangement spans correctly. Mixed-DPI displays
// share one backing-store ratio, so marks on a secondary display can scale
// slightly, but land in the right place.

// A normal accelerator — no native key hooks, no accessibility permission.
export const ANNOTATION_SHORTCUT = "CommandOrControl+Shift+A"

// Match assets/annotationOverlay.html's FADE_DURATION_MS (mirrored from
// src/annotationFade.ts). A graceful disable() asks the canvas to fade any
// lingering marks, then destroys the window once the fade has elapsed. Kept as
// a local literal because the electron tsconfig's rootDir is electron/ and
// can't import from src/; spec/desktop/annotation_overlay_spec.rb pins the
// three copies together.
const FADE_DURATION_MS = 2500

// Press-to-arm / auto-release timing. MIRRORED from src/annotationFade.ts (the
// tested source of truth) — can't import across the electron/src rootDir split,
// so annotation_overlay_spec.rb source-pins these copies to that module.
// - ARM_IDLE_RELEASE_MS: pointer-quiet window after which armed draw mode
//   auto-releases (no stroke in progress).
// - ARM_POLL_MS: how often the main process samples the renderer's idle
//   snapshot while armed.
// - MAX_ARMED_MS: hard safety cap; draw mode force-releases after this long
//   regardless of activity, so it can never stay stuck capturing the screen.
const ARM_IDLE_RELEASE_MS = 1200
const ARM_POLL_MS = 200
const MAX_ARMED_MS = 15000

// What enable() reports back: whether an annotation surface came up at all, and
// if so whether it's HOLD mode (native global-key hook) or the TAP fallback —
// so the recorder HUD shows the matching hint.
export type AnnotationEnableResult = { available: boolean; hold: boolean }

export type AnnotationController = {
  // Creates the overlay, then tries the HOLD hook and falls back to the TAP
  // shortcut. `available` is true only when a working surface came up (overlay
  // created AND — in tap mode — the accelerator registered); `hold` is true when
  // the native hold-to-draw hook is driving it. Tears down anything partial and
  // reports available:false when nothing could run, so callers degrade instead
  // of advertising a dead affordance. Never moves focus, never arms. Idempotent.
  enable: () => AnnotationEnableResult
  // Stops capturing input INSTANTLY, stops the hold hook, fades any lingering
  // marks, then destroys the overlay + unregisters the shortcut once the fade
  // elapses. The instant input release is the hard guarantee that the overlay
  // can never stay stuck over the screen. Safe to call when already disabled.
  disable: () => void
  isActive: () => boolean
  isDrawing: () => boolean
}

type Options = {
  // Absolute path to assets/annotationOverlay.html (resolved by the caller so
  // this module stays free of app.getAppPath() and stays unit-inspectable).
  overlayHtmlPath: string
  // Pushed on every draw-mode transition (armed / released) so the web
  // recorder's HUD can reflect the live state
  // (window.syrusShell.annotation.onModeChanged).
  onModeChanged: (drawing: boolean) => void
  // The global hold-to-draw hook factory — injectable so specs can drive the
  // hold path without the native module. Defaults to the real uiohook wrapper.
  holdHookFactory?: typeof startHoldToDrawHook
}

export const createAnnotationController = ({ overlayHtmlPath, onModeChanged, holdHookFactory = startHoldToDrawHook }: Options): AnnotationController => {
  let overlay: BrowserWindow | null = null
  // True while draw mode is armed (the overlay is capturing pointer input).
  let armed = false
  // Bumped on every arm/release transition. A pollIdle snapshot captures the
  // generation it was requested under; if a release→re-arm happened while its
  // renderer round-trip was in flight, the stale reply is ignored so it can
  // never auto-release a freshly re-armed session.
  let armGeneration = 0
  // Set while a graceful teardown fade is in flight (disable() scheduled the
  // destroy). Tracked so enable() can finish it before reusing the surface, so
  // the overlay's `closed` handler can cancel it, and so the destroy fires at
  // most once.
  let teardownTimer: ReturnType<typeof setTimeout> | null = null
  // While armed: the idle poll (samples the renderer to detect a pause and
  // auto-release) and the hard max-armed cap (force-release safety net). Both
  // cleared on every release / teardown so no stray timer outlives draw mode.
  let idlePollTimer: ReturnType<typeof setInterval> | null = null
  let maxArmedTimer: ReturnType<typeof setTimeout> | null = null
  // "hold" once the native global-key hook is driving arm/release; "tap" for the
  // fallback shortcut. Determines whether setArmed starts the auto-release
  // watchers (tap only — hold releases deterministically on key-up).
  let mode: "hold" | "tap" = "tap"
  // The live global-key hook in hold mode (null in tap mode); stopped on disable.
  let holdHook: HoldToDrawHook | null = null

  const overlayAlive = () => overlay !== null && !overlay.isDestroyed()

  // The union bounding box of every display, so the overlay covers the whole
  // virtual desktop and marks land on whichever monitor is being shared.
  const virtualDesktopBounds = () => {
    const displays = screen.getAllDisplays()
    const left = Math.min(...displays.map((d) => d.bounds.x))
    const top = Math.min(...displays.map((d) => d.bounds.y))
    const right = Math.max(...displays.map((d) => d.bounds.x + d.bounds.width))
    const bottom = Math.max(...displays.map((d) => d.bounds.y + d.bounds.height))
    return { x: left, y: top, width: right - left, height: bottom - top }
  }

  const clearTeardownTimer = () => {
    if (teardownTimer) {
      clearTimeout(teardownTimer)
      teardownTimer = null
    }
  }

  // Stop the auto-release watchers. Idempotent; called on every release path
  // (idle, Esc, re-tap, max cap, disable, teardown) so neither the idle poll
  // nor the hard cap can ever fire after draw mode has ended.
  const stopArmWatch = () => {
    if (idlePollTimer) {
      clearInterval(idlePollTimer)
      idlePollTimer = null
    }
    if (maxArmedTimer) {
      clearTimeout(maxArmedTimer)
      maxArmedTimer = null
    }
  }

  // Stop the native global-key hook (hold mode). Idempotent; called on every
  // teardown path so the OS-level hook never outlives the overlay.
  const stopHoldHook = () => {
    if (holdHook) {
      holdHook.stop()
      holdHook = null
    }
  }

  // Immediate, unconditional teardown: destroy the window + drop state. Used by
  // the fade timer, by a re-enable that pre-empts an in-flight fade, and on a
  // failed create.
  const destroyOverlayNow = () => {
    clearTeardownTimer()
    stopArmWatch()
    stopHoldHook()
    if (overlayAlive()) {
      overlay!.destroy()
    }
    overlay = null
    armed = false
    mode = "tap"
  }

  // The single place draw mode arms/releases. Flips OS-level input capture +
  // focus, starts/stops the auto-release watchers, mirrors the state to the
  // canvas, and pushes the transition to the HUD. Idempotent per state.
  const setArmed = (next: boolean) => {
    if (!overlayAlive() || next === armed) {
      return
    }

    armed = next
    armGeneration += 1
    // Capture pointer input only while armed; otherwise stay click-through so
    // the app under test is fully interactive. forward:true still delivers
    // move events for cursor feedback without swallowing clicks.
    overlay!.setIgnoreMouseEvents(!next, { forward: true })
    if (next) {
      // Grant keyboard focus ONLY in TAP mode — the tap flow needs the
      // before-input-event Escape handler to be reachable. In HOLD mode the pen
      // arms on EVERY physical Ctrl key-down (the global hook); taking focus
      // there would steal the keystream from the app under test and hijack the
      // user's ordinary Ctrl keyboard shortcuts (Ctrl+C, Ctrl+Tab, …) for the
      // whole recording. Pointer capture (setIgnoreMouseEvents above) is enough
      // for drawing; keyboard focus stays with the app. Release is on Ctrl key-up.
      if (mode === "tap") {
        overlay!.setFocusable(true)
        overlay!.focus()
        // Arm the auto-release watchers (poll for a pause, cap the session).
        startArmWatch()
      }
    } else {
      if (mode === "tap") {
        overlay!.blur()
        overlay!.setFocusable(false)
      }
      stopArmWatch()
    }

    // Mirror the armed state to the canvas: on arm it resets the idle clock; on
    // release it ends the in-flight stroke so it fades cleanly. Guarded +
    // best-effort; the window may be tearing down.
    overlay!.webContents
      .executeJavaScript(`window.__syrusAnnotation && window.__syrusAnnotation.setArmed(${next ? "true" : "false"})`)
      .catch(() => {})

    onModeChanged(next)
  }

  // Sample the renderer's idle snapshot; auto-release once the pointer has been
  // quiet for the whole idle window with no stroke in progress. Runs only while
  // armed. A mid-stroke pointer (active:true) is never cut off.
  const pollIdle = () => {
    if (!overlayAlive() || !armed) {
      return
    }
    // Tie this sample to the current arm session; a reply that resolves after a
    // release→re-arm belongs to a stale generation and must not act.
    const generation = armGeneration
    overlay!.webContents
      .executeJavaScript("window.__syrusAnnotation && window.__syrusAnnotation.idleSnapshot()")
      .then((snap: { active?: boolean; idleMs?: number } | null | undefined) => {
        if (!armed || armGeneration !== generation || !snap) {
          return
        }
        if (!snap.active && (snap.idleMs ?? 0) >= ARM_IDLE_RELEASE_MS) {
          setArmed(false)
        }
      })
      .catch(() => {})
  }

  const startArmWatch = () => {
    stopArmWatch()
    idlePollTimer = setInterval(pollIdle, ARM_POLL_MS)
    // Hard safety cap: force-release after MAX_ARMED_MS no matter what, even if
    // the idle poll wedges or the renderer stops reporting. The overlay must
    // never stay armed (capturing the whole screen) longer than this.
    maxArmedTimer = setTimeout(() => setArmed(false), MAX_ARMED_MS)
  }

  // The global-shortcut handler: tap to arm, tap again to release immediately.
  const toggleArm = () => setArmed(!armed)

  const enable = (): AnnotationEnableResult => {
    // A previous disable() may still be fading before its scheduled destroy.
    // Finish that teardown now rather than reusing a window that's about to be
    // destroyed out from under the new recording.
    if (teardownTimer) {
      destroyOverlayNow()
    }
    if (overlayAlive()) {
      return { available: true, hold: mode === "hold" }
    }

    try {
      const { x, y, width, height } = virtualDesktopBounds()

      overlay = new BrowserWindow({
        x,
        y,
        width,
        height,
        frame: false,
        transparent: true,
        hasShadow: false,
        resizable: false,
        movable: false,
        minimizable: false,
        maximizable: false,
        fullscreenable: false,
        skipTaskbar: true,
        // Created hidden + non-focusable, then shown with showInactive() below:
        // arming the overlay at record start must NEVER move focus off the app
        // the narrator is demonstrating. Draw mode grants focus explicitly
        // (setArmed), so an empty transparent overlay can't swallow the
        // narrator's keystrokes.
        show: false,
        focusable: false,
        alwaysOnTop: true,
        // No remote content ever loads here — a local, sandboxed canvas page.
        webPreferences: {
          contextIsolation: true,
          nodeIntegration: false,
          sandbox: true
        }
      })

      // Float above everything, including other apps and macOS fullscreen
      // spaces, so the user can annotate whatever they're demonstrating.
      overlay.setAlwaysOnTop(true, "screen-saver")
      overlay.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true })
      // Start click-through: the overlay must never block the app until the
      // user explicitly arms draw mode.
      overlay.setIgnoreMouseEvents(true, { forward: true })

      // Esc releases draw mode. Handled in-main via before-input-event so the
      // overlay needs no preload/IPC of its own. Draw mode grants focus, so the
      // keyDown reaches this handler; when not armed there's nothing to exit.
      overlay.webContents.on("before-input-event", (_event, input) => {
        if (input.type === "keyDown" && input.key === "Escape" && armed) {
          setArmed(false)
        }
      })

      overlay.on("closed", () => {
        clearTeardownTimer()
        stopArmWatch()
        stopHoldHook()
        overlay = null
        armed = false
        mode = "tap"
      })

      void overlay.loadFile(overlayHtmlPath)

      // Prefer HOLD-to-draw via the native global-key hook (Ctrl held → armed).
      // Set mode FIRST so the hook's arm/release don't start the tap-mode
      // auto-release watchers. The hook returns null when the native module or
      // (on macOS) Accessibility permission is unavailable — then fall through
      // to the tap shortcut.
      mode = "hold"
      holdHook = holdHookFactory({
        onHold: () => setArmed(true),
        onRelease: () => setArmed(false)
      })
      if (holdHook) {
        // Show WITHOUT activating — enable() must not move focus.
        overlay.showInactive()
        return { available: true, hold: true }
      }

      // Fall back to TAP mode. register() returns false (it does NOT throw) when
      // the accelerator is already owned by another app; a registered-but-false
      // shortcut would leave the HUD advertising a dead ⌘⇧A, so treat that as
      // unavailable — tear down and report failure.
      mode = "tap"
      if (!globalShortcut.register(ANNOTATION_SHORTCUT, toggleArm)) {
        destroyOverlayNow()
        return { available: false, hold: false }
      }

      // Show WITHOUT activating — enable() must not move focus.
      overlay.showInactive()

      return { available: true, hold: false }
    } catch {
      // Transparent always-on-top is compositor-dependent on Linux; on failure
      // tear down whatever partially came up and report unavailable so the
      // recorder simply omits the annotation affordance.
      try {
        globalShortcut.unregister(ANNOTATION_SHORTCUT)
      } catch {
        // never registered
      }
      destroyOverlayNow()
      return { available: false, hold: false }
    }
  }

  const disable = () => {
    // Free the accelerator immediately so a re-record — or another app — can
    // take it right away, independent of the visual fade below.
    try {
      globalShortcut.unregister(ANNOTATION_SHORTCUT)
    } catch {
      // never registered — fine
    }

    const wasArmed = armed
    armed = false
    // Kill the auto-release watchers AND the native hold hook on every disable
    // path so neither the idle poll, the max-armed cap, nor a global key hook can
    // fire after teardown.
    stopArmWatch()
    stopHoldHook()

    if (!overlayAlive()) {
      // Nothing to tear down (already disabled / already destroyed). Still
      // leave the HUD consistent if we were mid-draw.
      clearTeardownTimer()
      if (wasArmed) {
        onModeChanged(false)
      }
      return
    }

    // Stop capturing input INSTANTLY — the overlay must never trap pointer or
    // keyboard while it fades out. This is the hard "never stuck capturing"
    // guarantee, and it holds even when disable() runs from a renderer crash or
    // reload teardown.
    overlay!.setIgnoreMouseEvents(true, { forward: true })
    overlay!.blur()
    overlay!.setFocusable(false)

    // Fade any lingering marks, then destroy once the fade elapses, so stopping
    // a recording clears marks gracefully instead of a hard vanish. Best-effort
    // — the overlay renderer may already be gone.
    overlay!.webContents
      .executeJavaScript("window.__syrusAnnotation && window.__syrusAnnotation.clear()")
      .catch(() => {})

    // Leave the HUD in a consistent "not drawing" state if we tore down mid-draw.
    if (wasArmed) {
      onModeChanged(false)
    }

    // Idempotent: keep an already-scheduled teardown rather than stacking one.
    if (!teardownTimer) {
      teardownTimer = setTimeout(destroyOverlayNow, FADE_DURATION_MS)
    }
  }

  return {
    enable,
    disable,
    isActive: overlayAlive,
    isDrawing: () => armed
  }
}
