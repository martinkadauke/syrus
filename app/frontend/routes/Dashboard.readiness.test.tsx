import { render, screen, waitFor } from "@testing-library/react"
import { MemoryRouter } from "react-router-dom"
import { afterEach, describe, expect, it, vi } from "vitest"
import type { BootstrapPayload } from "../api/bootstrap"
import { resetBackendUpdateStoreForTests } from "../hooks/useBackendUpdate"
import { ReadinessPanel } from "./Dashboard"

type Readiness = NonNullable<NonNullable<BootstrapPayload["setup_status"]>["readiness"]>

const failingReadiness: Readiness = {
  status: "error",
  checks: [
    {
      key: "github",
      label: "GitHub credentials",
      status: "error",
      message: "GitHub credentials missing.",
      remediation: "Add a personal access token.",
      optional: false
    }
  ]
}

function renderPanel(readiness: Readiness) {
  return render(
    <MemoryRouter>
      <ReadinessPanel prefix="" readiness={readiness} />
    </MemoryRouter>
  )
}

describe("ReadinessPanel", () => {
  afterEach(() => {
    delete window.syrusShell
    resetBackendUpdateStoreForTests()
  })

  it("shows failing readiness checks in a plain browser", () => {
    renderPanel(failingReadiness)

    expect(screen.getByText("GitHub credentials missing.")).toBeInTheDocument()
  })

  it("suppresses the failing checks while the desktop shell updates the backend", async () => {
    // The checks fail BECAUSE the backend is deliberately unreachable —
    // showing "GitHub credentials missing" here is the exact scare this
    // feature exists to prevent. The sidebar's update notice explains the
    // outage instead; the panel returns once the update finishes.
    window.syrusShell = {
      getState: vi.fn().mockResolvedValue({
        updateReadyVersion: null,
        claudeDetected: false,
        skillInstalled: false,
        skillOfferDismissed: true,
        backendUpdate: { phase: "starting", percent: null }
      }),
      onStateChanged: vi.fn().mockReturnValue(() => {}),
      relaunchToUpdate: vi.fn(),
      installSkill: vi.fn(),
      dismissSkillOffer: vi.fn()
    }
    resetBackendUpdateStoreForTests()

    renderPanel(failingReadiness)

    await waitFor(() => expect(screen.queryByText("GitHub credentials missing.")).not.toBeInTheDocument())
  })
})
