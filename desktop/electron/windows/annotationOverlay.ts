import { BrowserWindow, globalShortcut, screen } from "electron"

// Red-pen screen annotation during a walkthrough recording. The overlay is a
// frameless, transparent, always-on-top window spanning EVERY display; the
// walkthrough recorder's full-screen getDisplayMedia captures it INCIDENTALLY,
// so marks the user draws are burned into the recorded video with no change to
// the capture pipeline. Draw mode is a global-shortcut TOGGLE (not hold-Ctrl):
// a reliable OS-wide accelerator that needs no native hooks and no macOS
// accessibility permission, and auto-fading strokes deliver the same "marks
// appear, then disappear" intent as a momentary hold. See
// assets/annotationOverlay.html for the canvas + fade renderer.
//
// Focus discipline (never steal the narrator's keystrokes): the overlay is
// created NON-ACTIVATING (focusable:false, shown with showInactive) so arming
// it at record start never moves focus off the app under test. Focus is granted
// ONLY while in draw mode — the canvas needs pointer input and the Escape key —
// and dropped again the instant draw mode ends. enable() itself never moves
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

export type AnnotationController = {
  // Creates the overlay + registers the draw-mode shortcut. Returns TRUE only
  // when the overlay exists AND the shortcut is actually registered; returns
  // false (after tearing down anything partial) when the overlay can't be
  // created or the accelerator is already owned, so callers degrade instead of
  // advertising a dead affordance. Never moves focus. Idempotent.
  enable: () => boolean
  // Stops capturing input INSTANTLY, fades any lingering marks, then destroys
  // the overlay + unregisters the shortcut once the fade elapses. The instant
  // input release is the hard guarantee that the overlay can never stay stuck
  // over the screen. Safe to call when already disabled. Idempotent.
  disable: () => void
  isActive: () => boolean
  isDrawing: () => boolean
}

type Options = {
  // Absolute path to assets/annotationOverlay.html (resolved by the caller so
  // this module stays free of app.getAppPath() and stays unit-inspectable).
  overlayHtmlPath: string
  // Pushed on every draw-mode transition so the web recorder's HUD can reflect
  // the live state (window.syrusShell.annotation.onModeChanged).
  onModeChanged: (drawing: boolean) => void
}

export const createAnnotationController = ({ overlayHtmlPath, onModeChanged }: Options): AnnotationController => {
  let overlay: BrowserWindow | null = null
  let drawing = false
  // Set while a graceful teardown fade is in flight (disable() scheduled the
  // destroy). Tracked so enable() can finish it before reusing the surface, so
  // the overlay's `closed` handler can cancel it, and so the destroy fires at
  // most once.
  let teardownTimer: ReturnType<typeof setTimeout> | null = null

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

  // Immediate, unconditional teardown: destroy the window + drop state. Used by
  // the fade timer, by a re-enable that pre-empts an in-flight fade, and on a
  // failed create.
  const destroyOverlayNow = () => {
    clearTeardownTimer()
    if (overlayAlive()) {
      overlay!.destroy()
    }
    overlay = null
    drawing = false
  }

  const setDrawing = (next: boolean) => {
    if (!overlayAlive()) {
      return
    }

    drawing = next
    // Capture pointer input only while drawing; otherwise stay click-through so
    // the app under test is fully interactive. forward:true still delivers
    // move events for cursor feedback without swallowing clicks.
    overlay!.setIgnoreMouseEvents(!next, { forward: true })
    if (next) {
      // Grant focus ONLY in draw mode: the canvas needs pointer input and the
      // before-input-event Escape handler needs keyboard focus. enable() never
      // moves focus (the overlay is non-activating), so this is the single
      // place the overlay is allowed to take focus.
      overlay!.setFocusable(true)
      overlay!.focus()
    } else {
      overlay!.blur()
      overlay!.setFocusable(false)
    }

    // Tell the canvas to release the in-flight stroke when leaving draw mode so
    // it fades cleanly. Guarded + best-effort; the window may be tearing down.
    overlay!.webContents
      .executeJavaScript(`window.__syrusAnnotation && window.__syrusAnnotation.setDrawing(${next ? "true" : "false"})`)
      .catch(() => {})

    onModeChanged(next)
  }

  const toggleDraw = () => setDrawing(!drawing)

  const enable = (): boolean => {
    // A previous disable() may still be fading before its scheduled destroy.
    // Finish that teardown now rather than reusing a window that's about to be
    // destroyed out from under the new recording.
    if (teardownTimer) {
      destroyOverlayNow()
    }
    if (overlayAlive()) {
      return true
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
        // (setDrawing), so an empty transparent overlay can't swallow the
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
      // user explicitly enters draw mode.
      overlay.setIgnoreMouseEvents(true, { forward: true })

      // Esc leaves draw mode. Handled in-main via before-input-event so the
      // overlay needs no preload/IPC of its own. Draw mode grants focus, so the
      // keyDown reaches this handler; outside draw mode there's nothing to exit.
      overlay.webContents.on("before-input-event", (_event, input) => {
        if (input.type === "keyDown" && input.key === "Escape" && drawing) {
          setDrawing(false)
        }
      })

      overlay.on("closed", () => {
        clearTeardownTimer()
        overlay = null
        drawing = false
      })

      void overlay.loadFile(overlayHtmlPath)

      // Register the draw-mode toggle. register() returns false (it does NOT
      // throw) when the accelerator is already owned by another app; a
      // registered-but-false shortcut would leave the HUD advertising a dead
      // ⌘⇧A, so treat that as unavailable — tear down and report failure. (No
      // fallback accelerator: the recorder HUD's shortcut label is static, so
      // silently binding a different key would itself be a misleading
      // affordance.)
      if (!globalShortcut.register(ANNOTATION_SHORTCUT, toggleDraw)) {
        destroyOverlayNow()
        return false
      }

      // Show WITHOUT activating — enable() must not move focus.
      overlay.showInactive()

      return true
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
      return false
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

    const wasDrawing = drawing
    drawing = false

    if (!overlayAlive()) {
      // Nothing to tear down (already disabled / already destroyed). Still
      // leave the HUD consistent if we were mid-draw.
      clearTeardownTimer()
      if (wasDrawing) {
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
    if (wasDrawing) {
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
    isDrawing: () => drawing
  }
}
