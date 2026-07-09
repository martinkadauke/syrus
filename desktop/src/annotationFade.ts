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
