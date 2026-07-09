import { describe, expect, it } from "vitest"
import {
  ARM_IDLE_RELEASE_MS,
  ARM_POLL_MS,
  armCapReached,
  canvasBackingSize,
  FADE_DURATION_MS,
  isStrokeFaded,
  MAX_ARMED_MS,
  shouldAutoReleaseOnIdle,
  STROKE_WIDTH,
  strokeAlpha
} from "./annotationFade"

describe("strokeAlpha", () => {
  it("is fully opaque at the moment of release", () => {
    expect(strokeAlpha(1_000, 1_000)).toBe(1)
  })

  it("treats a still-active stroke (released in the future) as fully opaque", () => {
    // The render loop passes `now` for an active stroke, but guard the
    // negative-age case regardless.
    expect(strokeAlpha(1_000, 1_500)).toBe(1)
  })

  it("is half faded at half the fade window", () => {
    expect(strokeAlpha(1_000 + FADE_DURATION_MS / 2, 1_000)).toBeCloseTo(0.5, 5)
  })

  it("reaches zero exactly at the fade window and stays there", () => {
    expect(strokeAlpha(1_000 + FADE_DURATION_MS, 1_000)).toBe(0)
    expect(strokeAlpha(1_000 + FADE_DURATION_MS * 3, 1_000)).toBe(0)
  })

  it("honors a custom fade duration", () => {
    expect(strokeAlpha(500, 0, 1_000)).toBeCloseTo(0.5, 5)
  })

  it("is zero when the fade duration is non-positive (never lingers)", () => {
    expect(strokeAlpha(0, 0, 0)).toBe(0)
    expect(strokeAlpha(0, 0, -100)).toBe(0)
  })
})

describe("isStrokeFaded", () => {
  it("is false while the stroke still has any opacity", () => {
    expect(isStrokeFaded(1_000 + FADE_DURATION_MS - 1, 1_000)).toBe(false)
  })

  it("is true once the fade window has fully elapsed", () => {
    expect(isStrokeFaded(1_000 + FADE_DURATION_MS, 1_000)).toBe(true)
  })
})

describe("canvasBackingSize", () => {
  it("scales CSS pixels by the device pixel ratio", () => {
    expect(canvasBackingSize(800, 2)).toBe(1_600)
  })

  it("floors fractional device pixels", () => {
    expect(canvasBackingSize(100, 1.5)).toBe(150)
    expect(canvasBackingSize(101, 1.5)).toBe(151) // 151.5 -> 151
  })

  it("falls back to a 1x ratio when the dpr is unknown", () => {
    expect(canvasBackingSize(640, 0)).toBe(640)
    expect(canvasBackingSize(640, -1)).toBe(640)
  })

  it("never returns a zero-sized backing store", () => {
    expect(canvasBackingSize(0, 2)).toBe(1)
  })
})

describe("shared drawing constants", () => {
  it("pins the fade window and pen width the overlay HTML mirrors", () => {
    expect(FADE_DURATION_MS).toBe(2500)
    expect(STROKE_WIDTH).toBe(6)
  })
})

describe("shouldAutoReleaseOnIdle", () => {
  it("does NOT release while a stroke is in progress, however long it idles", () => {
    // A mid-stroke pointer held still (moves stop firing) must never be cut off.
    expect(shouldAutoReleaseOnIdle(ARM_IDLE_RELEASE_MS, true)).toBe(false)
    expect(shouldAutoReleaseOnIdle(ARM_IDLE_RELEASE_MS * 100, true)).toBe(false)
  })

  it("releases once the idle window fully elapses with no active stroke", () => {
    expect(shouldAutoReleaseOnIdle(ARM_IDLE_RELEASE_MS, false)).toBe(true)
    expect(shouldAutoReleaseOnIdle(ARM_IDLE_RELEASE_MS + 500, false)).toBe(true)
  })

  it("stays armed until the idle window is reached", () => {
    expect(shouldAutoReleaseOnIdle(0, false)).toBe(false)
    expect(shouldAutoReleaseOnIdle(ARM_IDLE_RELEASE_MS - 1, false)).toBe(false)
  })

  it("auto-releases an accidental arm the user never drew on", () => {
    // Arm, then no pointer activity at all: idleMs keeps climbing, no stroke,
    // so it releases as soon as the window passes — an accidental tap can't
    // leave the overlay lingering over the screen.
    expect(shouldAutoReleaseOnIdle(ARM_IDLE_RELEASE_MS + 1, false)).toBe(true)
  })

  it("honors a custom idle window", () => {
    expect(shouldAutoReleaseOnIdle(500, false, 400)).toBe(true)
    expect(shouldAutoReleaseOnIdle(300, false, 400)).toBe(false)
  })
})

describe("armCapReached", () => {
  it("is false before the hard cap and true at/after it", () => {
    expect(armCapReached(0)).toBe(false)
    expect(armCapReached(MAX_ARMED_MS - 1)).toBe(false)
    expect(armCapReached(MAX_ARMED_MS)).toBe(true)
    expect(armCapReached(MAX_ARMED_MS + 5_000)).toBe(true)
  })

  it("honors a custom cap", () => {
    expect(armCapReached(1_000, 900)).toBe(true)
    expect(armCapReached(800, 900)).toBe(false)
  })
})

describe("press-to-arm timing constants", () => {
  it("pins the idle window, poll interval, and hard cap the overlay mirrors", () => {
    // annotationOverlay.ts (rootDir electron/, can't import src/) re-declares
    // these as literals; annotation_overlay_spec.rb source-pins the two copies.
    expect(ARM_IDLE_RELEASE_MS).toBe(1_200)
    expect(ARM_POLL_MS).toBe(200)
    expect(MAX_ARMED_MS).toBe(15_000)
    // The poll must be well under the idle window so release feels prompt.
    expect(ARM_POLL_MS).toBeLessThan(ARM_IDLE_RELEASE_MS)
    // The hard cap must be well beyond the idle window so it's only a safety net.
    expect(MAX_ARMED_MS).toBeGreaterThan(ARM_IDLE_RELEASE_MS)
  })
})
