import { fireEvent, render, screen } from "@testing-library/react"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import { RuntimeSetup } from "./RuntimeSetup"

type RuntimeSetupProps = Parameters<typeof RuntimeSetup>[0]

function renderRuntimeSetup(overrides: Partial<RuntimeSetupProps> = {}) {
  const props: RuntimeSetupProps = {
    mode: "missing",
    polling: false,
    onInstallWsl: vi.fn(),
    onDownload: vi.fn(),
    onRetry: vi.fn(),
    onBack: vi.fn(),
    ...overrides
  }
  render(<RuntimeSetup {...props} />)
  return props
}

describe("RuntimeSetup on Windows", () => {
  beforeEach(() => {
    ;(window as unknown as { syrusDesktop: unknown }).syrusDesktop = { platform: "win32" }
  })

  afterEach(() => {
    delete (window as unknown as { syrusDesktop?: unknown }).syrusDesktop
  })

  it("offers the one-click WSL 2 install when WSL is missing", () => {
    const { onInstallWsl } = renderRuntimeSetup({ wslMissing: true })

    expect(screen.getByTestId("wsl-step")).toBeTruthy()
    fireEvent.click(screen.getByRole("button", { name: "Install WSL 2" }))
    expect(onInstallWsl).toHaveBeenCalledTimes(1)
  })

  it("hides the WSL step when WSL is already present", () => {
    renderRuntimeSetup({ wslMissing: false })

    expect(screen.queryByTestId("wsl-step")).toBeNull()
  })

  it("recommends Docker Desktop and never mentions Podman", () => {
    // Shipped product decision: Podman compose is unsupported, so the guided
    // setup must not suggest installing it (install.ps1's exit-10 copy pins
    // the same rule in install_parity_spec).
    renderRuntimeSetup({ wslMissing: true })

    expect(screen.getByRole("button", { name: /Download Docker Desktop/ })).toBeTruthy()
    expect(screen.queryByText(/Podman/)).toBeNull()
  })
})
