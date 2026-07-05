import { describe, expect, it } from "vitest"
import { computePopoverPosition } from "../electron/windows/popoverPosition"

// The popover window is 360×480 (createPopoverWindow).
const windowBounds = { width: 360, height: 480 }

describe("computePopoverPosition", () => {
  it("opens below a mac menu-bar tray, centered on the icon with no gap", () => {
    const { x, y } = computePopoverPosition({
      trayBounds: { x: 1300, y: 0, width: 24, height: 24 },
      windowBounds,
      workArea: { x: 0, y: 0, width: 1512, height: 957 },
      platform: "darwin"
    })

    // Centered under the tray icon: round(1312 - 180).
    expect(x).toBe(1132)
    // Flush below the menu-bar icon — darwin has no vertical offset.
    expect(y).toBe(24)
  })

  it("opens ABOVE the tray when a Windows bottom taskbar puts it in the lower half", () => {
    const trayBounds = { x: 1700, y: 1040, width: 24, height: 24 }
    const { x, y } = computePopoverPosition({
      trayBounds,
      windowBounds,
      workArea: { x: 0, y: 0, width: 1920, height: 1040 },
      platform: "win32"
    })

    // trayBounds.y - windowBounds.height - 4: the whole popover sits above
    // the taskbar instead of falling off the bottom of the screen.
    expect(y).toBe(1040 - 480 - 4)
    expect(y).toBeLessThan(trayBounds.y)
    expect(x).toBe(1532)
  })

  it("clamps x so the popover stays inside the right edge of the work area", () => {
    const workArea = { x: 0, y: 0, width: 1920, height: 1040 }
    const { x } = computePopoverPosition({
      trayBounds: { x: 1890, y: 1040, width: 24, height: 24 },
      windowBounds,
      workArea,
      platform: "win32"
    })

    // Unclamped would be 1722; the right edge caps it at workArea right - width.
    expect(x).toBe(workArea.x + workArea.width - windowBounds.width)
  })

  it("clamps x to the work-area origin on the left edge (non-zero multi-monitor origin)", () => {
    const workArea = { x: 1920, y: 0, width: 1920, height: 1040 }
    const { x } = computePopoverPosition({
      trayBounds: { x: 1930, y: 1040, width: 24, height: 24 },
      windowBounds,
      workArea,
      platform: "win32"
    })

    // Unclamped would be 1762, off the left of this display's work area.
    expect(x).toBe(workArea.x)
  })

  it("offsets 4px below a top-of-screen tray on non-darwin platforms only", () => {
    const topTray = {
      trayBounds: { x: 900, y: 0, width: 24, height: 24 },
      windowBounds,
      workArea: { x: 0, y: 0, width: 1920, height: 1160 }
    }

    expect(computePopoverPosition({ ...topTray, platform: "darwin" }).y).toBe(24)
    expect(computePopoverPosition({ ...topTray, platform: "win32" }).y).toBe(28)
    expect(computePopoverPosition({ ...topTray, platform: "linux" }).y).toBe(28)
  })
})
