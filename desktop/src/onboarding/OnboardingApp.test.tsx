import { render, screen } from "@testing-library/react"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import { OnboardingApp } from "./OnboardingApp"

function stubBridge(initialState: SyrusOnboardingState) {
  const bridge = {
    getOnboardingState: vi.fn().mockResolvedValue(initialState),
    onOnboardingState: vi.fn().mockReturnValue(() => {}),
    onOnboardingLogLine: vi.fn().mockReturnValue(() => {}),
    onboardingBack: vi.fn(),
    chooseOnboardingMode: vi.fn(),
    connectRemote: vi.fn(),
    retryOnboarding: vi.fn(),
    finishOnboarding: vi.fn()
  }
  ;(window as unknown as { syrusDesktop: unknown }).syrusDesktop = bridge
  return bridge
}

describe("OnboardingApp layout", () => {
  beforeEach(() => {
    stubBridge({ phase: "done", mode: "local", url: "http://localhost:3000" } as SyrusOnboardingState)
  })

  afterEach(() => {
    vi.restoreAllMocks()
    delete (window as unknown as { syrusDesktop?: unknown }).syrusDesktop
  })

  it("vertically centers short content instead of top-aligning it", async () => {
    render(<OnboardingApp />)

    await screen.findByText("Syrus is installed and running")
    const wrapper = screen.getByTestId("onboarding-content")
    // my-auto centers when content is shorter than the window but still
    // lets tall content scroll from the top (items-center would clip it).
    expect(wrapper.className).toContain("my-auto")
    expect(wrapper.className).toContain("justify-center")
    expect(wrapper.parentElement?.className).not.toContain("items-start")
  })
})
