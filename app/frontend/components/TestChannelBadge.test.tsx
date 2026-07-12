import { render, screen } from "@testing-library/react"
import { afterEach, describe, expect, it, vi } from "vitest"
import { TestChannelBadge } from "./TestChannelBadge"

const stableUa = "Mozilla/5.0 Chrome/130.0.0.0 Electron/39.8.10 SyrusDesktop/0.1.5 SyrusDesktopBuild/0.1.5 Safari/537.36"
const testUa =
  "Mozilla/5.0 Chrome/130.0.0.0 Electron/39.8.10 SyrusDesktop/0.1.5-test.3 SyrusDesktopBuild/0.1.5-test.3 SyrusDesktopChannel/test Safari/537.36"

describe("TestChannelBadge", () => {
  afterEach(() => vi.restoreAllMocks())

  it("renders nothing in a plain browser", () => {
    render(<TestChannelBadge />)
    expect(screen.queryByTestId("test-channel-badge")).toBeNull()
  })

  it("renders nothing on the stable channel (no SyrusDesktopChannel token)", () => {
    vi.spyOn(navigator, "userAgent", "get").mockReturnValue(stableUa)
    render(<TestChannelBadge />)
    expect(screen.queryByTestId("test-channel-badge")).toBeNull()
  })

  it("shows an amber TEST pill inside a test build", () => {
    vi.spyOn(navigator, "userAgent", "get").mockReturnValue(testUa)
    render(<TestChannelBadge />)
    const badge = screen.getByTestId("test-channel-badge")
    expect(badge.textContent).toBe("Test")
    expect(badge.className).toContain("amber")
    expect(badge.getAttribute("title")).toContain("test build")
  })
})
