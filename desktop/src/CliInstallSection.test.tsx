import { fireEvent, render, screen, waitFor } from "@testing-library/react"
import { afterEach, describe, expect, it, vi } from "vitest"
import { CliInstallSection } from "./App"

function stubBridge(over: Partial<{ available: boolean; install: SyrusCliInstallResult }> = {}) {
  const bridge = {
    syrusCliStatus: vi.fn().mockResolvedValue({ available: over.available ?? false }),
    installSyrusCli: vi.fn().mockResolvedValue(
      over.install ?? {
        installed: true,
        target: "/Users/op/.local/bin/syrus",
        onPath: false,
        signedIn: true,
        skillInstalled: false,
        skillError: null,
        error: null
      }
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

  it("shows installed state with a skill button instead of Install CLI", async () => {
    stubBridge({ available: true })
    render(<CliInstallSection />)
    await waitFor(() => expect(screen.queryByText(/Installed — Checkout/)).not.toBeNull())
    expect(screen.queryByRole("button", { name: /Install CLI/ })).toBeNull()
    expect(screen.queryByRole("button", { name: "Add Claude Code skill" })).not.toBeNull()
  })

  it("installs on click with the skill opt-in, reports auto-login and the PATH hint", async () => {
    const bridge = stubBridge({ available: false })
    render(<CliInstallSection />)

    fireEvent.click(await screen.findByRole("button", { name: "Install CLI" }))
    // The skill checkbox defaults to checked and rides along with the install.
    expect(bridge.installSyrusCli).toHaveBeenCalledWith({ withSkill: true })

    await waitFor(() => expect(screen.queryByText(/Installed to \/Users\/op\/.local\/bin\/syrus/)).not.toBeNull())
    expect(screen.queryByText(/already signed in via this app.s credentials/)).not.toBeNull()
    // ~/.local/bin wasn't on PATH — the export one-liner is offered.
    expect(screen.queryByText(/export PATH=/)).not.toBeNull()
  })

  it("skips the skill when the opt-in is unchecked", async () => {
    const bridge = stubBridge({ available: false })
    render(<CliInstallSection />)

    fireEvent.click(await screen.findByRole("checkbox"))
    fireEvent.click(await screen.findByRole("button", { name: "Install CLI" }))
    expect(bridge.installSyrusCli).toHaveBeenCalledWith({ withSkill: false })
  })

  it("reports the skill outcome alongside the install", async () => {
    stubBridge({
      available: false,
      install: {
        installed: true,
        target: "/Users/op/.local/bin/syrus",
        onPath: true,
        signedIn: true,
        skillInstalled: true,
        skillError: null,
        error: null
      }
    })
    render(<CliInstallSection />)

    fireEvent.click(await screen.findByRole("button", { name: "Install CLI" }))
    await waitFor(() => expect(screen.queryByText(/Claude Code skill added/)).not.toBeNull())
  })

  it("surfaces install failures", async () => {
    stubBridge({
      available: false,
      install: {
        installed: false,
        target: null,
        onPath: false,
        signedIn: false,
        skillInstalled: false,
        skillError: null,
        error: "bundled binary missing"
      }
    })
    render(<CliInstallSection />)

    fireEvent.click(await screen.findByRole("button", { name: "Install CLI" }))
    await waitFor(() => expect(screen.queryByText("bundled binary missing")).not.toBeNull())
  })
})
