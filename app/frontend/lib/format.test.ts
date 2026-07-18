import { describe, expect, it } from "vitest"
import { formatBytes } from "./format"

describe("formatBytes", () => {
  it("formats B / KB / MB", () => {
    expect(formatBytes(0)).toBe("0 B")
    expect(formatBytes(512)).toBe("512 B")
    expect(formatBytes(2048)).toBe("2.0 KB")
    expect(formatBytes(5 * 1024 * 1024)).toBe("5.0 MB")
  })

  it("returns 'unknown size' for null/undefined", () => {
    expect(formatBytes(null)).toBe("unknown size")
    expect(formatBytes(undefined)).toBe("unknown size")
  })
})
