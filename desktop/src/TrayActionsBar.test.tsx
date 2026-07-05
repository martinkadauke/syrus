import { fireEvent, render, screen } from "@testing-library/react"
import { afterEach, describe, expect, it, vi } from "vitest"
import { TrayActionsBar } from "./App"

describe("TrayActionsBar", () => {
  afterEach(() => {
    vi.restoreAllMocks()
    delete (window as unknown as { syrusDesktop?: unknown }).syrusDesktop
  })

  it("exposes the context menu's essentials on the left-click popover", () => {
    const bridge = {
      openSyrusWindow: vi.fn().mockResolvedValue(undefined),
      showPreferences: vi.fn().mockResolvedValue(undefined),
      quitApp: vi.fn().mockResolvedValue(undefined)
    }
    ;(window as unknown as { syrusDesktop: unknown }).syrusDesktop = bridge

    render(<TrayActionsBar />)

    fireEvent.click(screen.getByRole("button", { name: "Open Syrus" }))
    expect(bridge.openSyrusWindow).toHaveBeenCalled()
    fireEvent.click(screen.getByRole("button", { name: "Preferences" }))
    expect(bridge.showPreferences).toHaveBeenCalled()
    fireEvent.click(screen.getByRole("button", { name: "Quit" }))
    expect(bridge.quitApp).toHaveBeenCalled()
  })
})
