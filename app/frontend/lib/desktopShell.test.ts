import { afterEach, describe, expect, it, vi } from "vitest"
import { isDesktopShell, openInNewTab } from "./desktopShell"

const desktopUa = "Mozilla/5.0 (Macintosh) Chrome/130.0.0.0 Electron/39.8.10 SyrusDesktop/0.1.0 Safari/537.36"
const browserUa = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15"

describe("isDesktopShell", () => {
  afterEach(() => vi.restoreAllMocks())

  it("detects the SyrusDesktop user-agent marker", () => {
    vi.spyOn(navigator, "userAgent", "get").mockReturnValue(desktopUa)
    expect(isDesktopShell()).toBe(true)
  })

  it("is false in a plain browser", () => {
    vi.spyOn(navigator, "userAgent", "get").mockReturnValue(browserUa)
    expect(isDesktopShell()).toBe(false)
  })
})

describe("openInNewTab", () => {
  afterEach(() => vi.restoreAllMocks())

  it("opens without the noopener feature (which would force a null return) and severs the opener", () => {
    const opened = { opener: {} as unknown }
    const openSpy = vi.spyOn(window, "open").mockReturnValue(opened as Window)

    expect(openInNewTab("https://example.com/auth")).toBe(true)
    expect(openSpy).toHaveBeenCalledWith("https://example.com/auth", "_blank")
    expect(opened.opener).toBeNull()
  })

  it("reports a genuinely blocked popup in a plain browser", () => {
    vi.spyOn(window, "open").mockReturnValue(null)
    vi.spyOn(navigator, "userAgent", "get").mockReturnValue(browserUa)

    expect(openInNewTab("https://example.com/auth")).toBe(false)
  })

  it("treats an intercepted open as success inside the desktop shell", () => {
    vi.spyOn(window, "open").mockReturnValue(null)
    vi.spyOn(navigator, "userAgent", "get").mockReturnValue(desktopUa)

    expect(openInNewTab("https://example.com/auth")).toBe(true)
  })

  it("survives a cross-origin handle that refuses opener assignment", () => {
    const hostile = {}
    Object.defineProperty(hostile, "opener", {
      set() {
        throw new DOMException("Blocked a frame from accessing a cross-origin frame.")
      }
    })
    vi.spyOn(window, "open").mockReturnValue(hostile as Window)

    expect(openInNewTab("https://example.com/auth")).toBe(true)
  })
})
