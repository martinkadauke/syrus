import { describe, expect, it } from "vitest"
import { paintUnreadDot } from "../electron/trayBadge"

// Mirrors the dot geometry contract in trayBadge.ts (radius = max(3,
// round(width * 0.22)), center anchored to the top-right corner). Recomputed
// here so a regression in the radius or placement math fails the pins below.
const dotGeometry = (width: number) => {
  const radius = Math.max(3, Math.round(width * 0.22))
  return { radius, centerX: width - radius - 1, centerY: radius + 1 }
}

const paintedPixels = (bitmap: Buffer, width: number, height: number) => {
  const painted: Array<{ x: number; y: number; offset: number }> = []
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const offset = (y * width + x) * 4
      if (
        bitmap[offset] !== 0 ||
        bitmap[offset + 1] !== 0 ||
        bitmap[offset + 2] !== 0 ||
        bitmap[offset + 3] !== 0
      ) {
        painted.push({ x, y, offset })
      }
    }
  }
  return painted
}

// 16 is the Windows tray icon size, 18 the mac one (createPlainTrayIcon).
describe.each([16, 18])("paintUnreadDot on a %d px square icon", (size) => {
  const freshBitmap = () => Buffer.alloc(size * size * 4)

  it("writes the badge color in BGRA byte order (blank-icon regression)", () => {
    const bitmap = freshBitmap()
    paintUnreadDot(bitmap, size, size)

    const painted = paintedPixels(bitmap, size, size)
    expect(painted.length).toBeGreaterThan(0)
    for (const { offset } of painted) {
      // B, G, R, A — an RGBA-ordered write would swap the 0x26/0xdc bytes.
      expect(bitmap[offset]).toBe(0x26)
      expect(bitmap[offset + 1]).toBe(0x26)
      expect(bitmap[offset + 2]).toBe(0xdc)
      expect(bitmap[offset + 3]).toBe(0xff)
    }
  })

  it("keeps the dot anchored to the top-right corner", () => {
    const bitmap = freshBitmap()
    paintUnreadDot(bitmap, size, size)

    const { radius, centerX, centerY } = dotGeometry(size)
    expect(centerX).toBeGreaterThan(size / 2)
    expect(centerY).toBeLessThan(size / 2)

    const painted = paintedPixels(bitmap, size, size)
    // The dot's center is painted, every painted pixel lies within the dot's
    // radius (at 16px the rim may graze one pixel past the midlines, so the
    // circle — not the quadrant — is the exact bound)...
    expect(painted).toContainEqual(expect.objectContaining({ x: centerX, y: centerY }))
    for (const { x, y } of painted) {
      expect((x - centerX) ** 2 + (y - centerY) ** 2).toBeLessThanOrEqual(radius * radius)
    }
    // ...and nothing ever lands in the bottom-left quadrant.
    expect(painted.some(({ x, y }) => x < size / 2 && y > size / 2)).toBe(false)
  })

  it("leaves every byte outside the dot's bounding box untouched", () => {
    const bitmap = freshBitmap()
    paintUnreadDot(bitmap, size, size)

    const { radius, centerX, centerY } = dotGeometry(size)
    for (let y = 0; y < size; y += 1) {
      for (let x = 0; x < size; x += 1) {
        if (Math.abs(x - centerX) <= radius && Math.abs(y - centerY) <= radius) {
          continue
        }
        const offset = (y * size + x) * 4
        expect(bitmap.subarray(offset, offset + 4)).toEqual(Buffer.alloc(4))
      }
    }
  })

  it("never writes out of bounds", () => {
    const bitmap = freshBitmap()
    expect(() => paintUnreadDot(bitmap, size, size)).not.toThrow()
    expect(bitmap.length).toBe(size * size * 4)
  })
})
