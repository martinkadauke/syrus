import { describe, expect, it } from "vitest"
import { decideOnSecondInstance, takeoverPrompt } from "../electron/instanceTakeover"

const installed = { version: "0.2.0", bundlePath: "/Users/op/Applications/Syrus.app" }
const dmgCopy = { version: "0.2.0", bundlePath: "/Volumes/Syrus 0.2.0/Syrus.app" }
const newer = { version: "0.3.0", bundlePath: "/Users/op/Applications/Syrus.app" }

describe("decideOnSecondInstance", () => {
  it("offers takeover when a different version launches", () => {
    expect(decideOnSecondInstance(installed, newer)).toBe("offer")
  })

  it("offers takeover when the same version launches from a different bundle (stale DMG copy)", () => {
    // The field failure: an old instance running off a mounted DMG silently
    // swallowed launches of the freshly installed copy for hours.
    expect(decideOnSecondInstance(dmgCopy, installed)).toBe("offer")
  })

  it("just focuses when the identical copy relaunches", () => {
    expect(decideOnSecondInstance(installed, { ...installed })).toBe("focus")
  })

  it("just focuses when the second launch sends no identity (older build)", () => {
    expect(decideOnSecondInstance(installed, undefined)).toBe("focus")
    expect(decideOnSecondInstance(installed, {})).toBe("focus")
    expect(decideOnSecondInstance(installed, { version: "0.3.0" })).toBe("focus")
  })
})

describe("takeoverPrompt", () => {
  it("names both copies and makes Switch the default", () => {
    const prompt = takeoverPrompt(dmgCopy, installed)
    expect(prompt.detail).toContain("/Volumes/Syrus 0.2.0/Syrus.app")
    expect(prompt.detail).toContain("/Users/op/Applications/Syrus.app")
    expect(prompt.buttons[prompt.switchIndex]).toBe("Switch to New Copy")
  })
})
