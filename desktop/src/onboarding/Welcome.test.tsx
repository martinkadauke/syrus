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

  it("offers the local install on Windows via Docker Desktop", () => {
    stubPlatform("win32")
    const onChoose = vi.fn()
    render(<Welcome onChoose={onChoose} />)

    // Phase 2 of docs/windows-desktop-plan.md: install.ps1 drives the local
    // path on Windows, so the card is a real choice now.
    fireEvent.click(screen.getByRole("button", { name: /Install on this PC/ }))
    expect(onChoose).toHaveBeenCalledWith("local")

    fireEvent.click(screen.getByRole("button", { name: /Connect to existing Syrus/ }))
    expect(onChoose).toHaveBeenCalledWith("remote")
  })
})
