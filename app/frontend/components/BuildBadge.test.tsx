import { render, screen } from "@testing-library/react"
import { afterEach, describe, expect, it, vi } from "vitest"
import { BuildBadge } from "./BuildBadge"

const desktopUa = "Mozilla/5.0 Chrome/130.0.0.0 Electron/39.8.10 SyrusDesktop/0.2.0 SyrusDesktopBuild/abc1234 Safari/537.36"

describe("BuildBadge", () => {
  afterEach(() => vi.restoreAllMocks())

  it("shows app and backend builds inside the desktop shell", () => {
    vi.spyOn(navigator, "userAgent", "get").mockReturnValue(desktopUa)
    render(<BuildBadge revision="439245a" />)
    expect(screen.getByTestId("build-badge").textContent).toBe("app abc1234 · backend 439245a")
  })

  it("shows only the backend build in a plain browser", () => {
    render(<BuildBadge revision="439245a" />)
    expect(screen.getByTestId("build-badge").textContent).toBe("backend 439245a")
  })

  it("renders nothing when there is nothing to say (dev backend, no shell)", () => {
    render(<BuildBadge revision="dev" />)
    expect(screen.queryByTestId("build-badge")).toBeNull()
  })
})
