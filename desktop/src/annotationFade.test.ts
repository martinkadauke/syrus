import { describe, expect, it } from "vitest"
import {
  canvasBackingSize,
  FADE_DURATION_MS,
  isStrokeFaded,
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
