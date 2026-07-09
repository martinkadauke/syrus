// Pure geometry + fade math for the red-pen annotation overlay canvas.
//
// The overlay is a standalone, sandboxed BrowserWindow that loads
// assets/annotationOverlay.html (created by
// electron/windows/annotationOverlay.ts). That page runs an inline script and
// can't import this module at runtime, so the HTML MIRRORS these constants and
// the strokeAlpha formula. This module is the tested source of truth — keep the
// two in sync. spec/desktop/annotation_overlay_spec.rb source-pins the shared
// constants in both files so a drift fails CI.

// Each stroke fades from full opacity to nothing over this window, starting
// when the pointer is lifted (so an in-progress stroke never fades mid-draw).
// ~2.5s keeps a mark on screen long enough to read while the narrator is
// describing that spot, then clears so the next mark reads cleanly.
export const FADE_DURATION_MS = 2500

// Thick, bright-red pen with an outer glow so the mark contrasts on any
// background (light UI, dark terminal, a photo). Width in CSS px.
export const STROKE_WIDTH = 6
export const STROKE_GLOW = 12

// Linear fade from 1 (just released) to 0 (fully faded), clamped outside the
// window. `releasedAt` is when the stroke stopped growing; an active stroke
// (releasedAt in the future / equal to now) reads as fully opaque.
export function strokeAlpha(now: number, releasedAt: number, fadeMs: number = FADE_DURATION_MS): number {
  if (fadeMs <= 0) return 0
  const age = now - releasedAt
  if (age <= 0) return 1
  if (age >= fadeMs) return 0
  return 1 - age / fadeMs
}

// A released stroke is prunable once it has fully faded — the render loop drops
// it so the stroke list can't grow without bound during a long recording.
export function isStrokeFaded(now: number, releasedAt: number, fadeMs: number = FADE_DURATION_MS): boolean {
  return strokeAlpha(now, releasedAt, fadeMs) <= 0
}

// Backing-store size for a crisp line on HiDPI displays: CSS px * devicePixel
// ratio, floored to whole device pixels and never below 1 (a 0-sized canvas
// throws on some platforms). dpr <= 0 (unknown) falls back to 1.
export function canvasBackingSize(cssSize: number, dpr: number): number {
  const ratio = dpr > 0 ? dpr : 1
  return Math.max(1, Math.floor(cssSize * ratio))
}

// --- press-to-arm / auto-release draw-mode timing -----------------------
//
// Draw mode is NOT a persistent toggle. Tapping ⌘/Ctrl+Shift+A ARMS the pen
// (the overlay starts capturing pointer input); it AUTO-RELEASES back to
// click-through the moment the user pauses, so the app under test stays
// interactive except during the brief window they're actively annotating.
//
// The decision math lives here (the tested source of truth) and is MIRRORED as
// literals in electron/windows/annotationOverlay.ts, which owns the OS-level
// input capture but can't import from src/ (its tsconfig rootDir is electron/).
// spec/desktop/annotation_overlay_spec.rb source-pins the two copies together.
//
// Why auto-release and not a true modifier-HOLD ("draw only while a key is
// physically down"): a real hold needs a GLOBAL keyboard hook, which on macOS
// demands Accessibility permission (a scary system prompt + a manual
// System-Settings toggle) and a native module (uiohook-napi) ABI-matched to
// Electron and bundled into the universal DMG + the Windows installer. This app
// has been bitten repeatedly by native/packaging fragility, so we deliberately
// avoid it. Auto-release delivers the same click-through benefit — the overlay
// only traps input while you're drawing — with ZERO native code and ZERO
// permission prompts. The native hold remains a possible future opt-in.

// Idle window: after the pointer goes quiet for this long with no stroke in
// progress, draw mode auto-releases. ~1.2s is long enough to lift the pen
// between strokes without dropping back to click-through, short enough that an
// accidental arm (or a finished mark) returns control almost immediately.
export const ARM_IDLE_RELEASE_MS = 1200

// How often the main process samples the renderer's idle snapshot while armed.
// Coarse enough to be free, fine enough that release feels instant.
export const ARM_POLL_MS = 200

// Hard safety cap: draw mode can NEVER stay armed (capturing input) longer than
// this, even if the idle poll wedges or the renderer stops reporting activity.
// When it elapses the overlay force-releases regardless, so the overlay can
// never get stuck trapping the whole screen.
export const MAX_ARMED_MS = 15_000

// Auto-release predicate: release once the pointer has been idle for the whole
// window AND no stroke is currently in progress. A mid-stroke pointer (button
// still down, held still) is never cut off — the release waits until the stroke
// ends and the idle window then elapses.
export function shouldAutoReleaseOnIdle(
  idleMs: number,
  activeStroke: boolean,
  idleReleaseMs: number = ARM_IDLE_RELEASE_MS
): boolean {
  if (activeStroke) return false
  return idleMs >= idleReleaseMs
}

// Hard-cap predicate: true once the overlay has been armed at least this long,
// regardless of activity. Drives the force-release safety net.
export function armCapReached(armedMs: number, capMs: number = MAX_ARMED_MS): boolean {
  return armedMs >= capMs
}
