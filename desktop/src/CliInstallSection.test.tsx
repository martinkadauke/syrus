import { fireEvent, render, screen, waitFor } from "@testing-library/react"
import { afterEach, describe, expect, it, vi } from "vitest"
import { CliInstallSection } from "./App"

function stubBridge(over: Partial<{ available: boolean; install: SyrusCliInstallResult }> = {}) {
  const bridge = {
    syrusCliStatus: vi.fn().mockResolvedValue({ available: over.available ?? false }),
    installSyrusCli: vi.fn().mockResolvedValue(
      over.install ?? { installed: true, target: "/Users/op/.local/bin/syrus", onPath: false, signedIn: true, error: null }
    )
  }
  ;(window as unknown as { syrusDesktop: unknown }).syrusDesktop = bridge
  return bridge
}

describe("CliInstallSection", () => {
  afterEach(() => {
    vi.restoreAllMocks()
    delete (window as unknown as { syrusDesktop?: unknown }).syrusDesktop
  })

  it("shows installed state without an install button", async () => {
    stubBridge({ available: true })
    render(<CliInstallSection />)
    await waitFor(() => expect(screen.queryByText(/Installed — Checkout/)).not.toBeNull())
    expect(screen.queryByRole("button", { name: /Install CLI/ })).toBeNull()
  })

  it("installs on click, reports auto-login and the PATH hint", async () => {
    const bridge = stubBridge({ available: false })
    render(<CliInstallSection />)

    fireEvent.click(await screen.findByRole("button", { name: "Install CLI" }))
    expect(bridge.installSyrusCli).toHaveBeenCalled()

    await waitFor(() => expect(screen.queryByText(/Installed to \/Users\/op\/.local\/bin\/syrus/)).not.toBeNull())
    expect(screen.queryByText(/already signed in via this app.s credentials/)).not.toBeNull()
    // ~/.local/bin wasn't on PATH — the export one-liner is offered.
    expect(screen.queryByText(/export PATH=/)).not.toBeNull()
  })

  it("surfaces install failures", async () => {
    stubBridge({
      available: false,
      install: { installed: false, target: null, onPath: false, signedIn: false, error: "bundled binary missing" }
    })
    render(<CliInstallSection />)

    fireEvent.click(await screen.findByRole("button", { name: "Install CLI" }))
    await waitFor(() => expect(screen.queryByText("bundled binary missing")).not.toBeNull())
  })
})
