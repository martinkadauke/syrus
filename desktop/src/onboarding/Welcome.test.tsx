import { fireEvent, render, screen } from "@testing-library/react"
import { afterEach, describe, expect, it, vi } from "vitest"
import { Welcome } from "./Welcome"

function stubPlatform(platform: string) {
  ;(window as unknown as { syrusDesktop: unknown }).syrusDesktop = { platform }
}

describe("Welcome", () => {
  afterEach(() => {
    vi.restoreAllMocks()
    delete (window as unknown as { syrusDesktop?: unknown }).syrusDesktop
  })

  it("offers the local install on macOS", () => {
    stubPlatform("darwin")
    const onChoose = vi.fn()
    render(<Welcome onChoose={onChoose} />)

    fireEvent.click(screen.getByRole("button", { name: /Install on this Mac/ }))
    expect(onChoose).toHaveBeenCalledWith("local")
  })

  it("labels local install as upcoming on Windows and only offers connect", () => {
    stubPlatform("win32")
    const onChoose = vi.fn()
    render(<Welcome onChoose={onChoose} />)

    // Phase 1 of docs/windows-desktop-plan.md: no PowerShell installer yet,
    // so the local card is informational (Docker Desktop / Podman Desktop
    // guidance), not clickable.
    expect(screen.queryByText("Install on this PC")).not.toBeNull()
    expect(screen.queryByText(/Docker Desktop or Podman/)).not.toBeNull()
    expect(screen.queryByRole("button", { name: /Install on this PC/ })).toBeNull()

    fireEvent.click(screen.getByRole("button", { name: /Connect to existing Syrus/ }))
    expect(onChoose).toHaveBeenCalledWith("remote")
  })
})
