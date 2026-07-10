import { act, render, screen, waitFor } from "@testing-library/react"
import { afterEach, describe, expect, it, vi } from "vitest"
import type { SyrusShellBridge, SyrusShellState } from "../lib/desktopShell"
import { resetBackendUpdateStoreForTests, useBackendUpdate, useBackendUpdating } from "./useBackendUpdate"

function shellState(overrides: Partial<SyrusShellState> = {}): SyrusShellState {
  return {
    updateReadyVersion: null,
    claudeDetected: false,
    skillInstalled: false,
    skillOfferDismissed: false,
    backendUpdate: null,
    ...overrides
  }
}

function installBridge(state: Partial<SyrusShellState> = {}, overrides: Partial<SyrusShellBridge> = {}): SyrusShellBridge {
  const bridge: SyrusShellBridge = {
    getState: vi.fn().mockResolvedValue(shellState(state)),
    onStateChanged: vi.fn().mockReturnValue(() => {}),
    relaunchToUpdate: vi.fn(),
    installSkill: vi.fn().mockResolvedValue({ ok: true, message: "" }),
    dismissSkillOffer: vi.fn(),
    ...overrides
  }
  window.syrusShell = bridge
  return bridge
}

function Probe() {
  const update = useBackendUpdate()
  const updating = useBackendUpdating()
  return (
    <div>
      <span data-testid="updating">{String(updating)}</span>
      <span data-testid="phase">{update ? `${update.phase}:${update.percent ?? "-"}` : "none"}</span>
    </div>
  )
}

describe("useBackendUpdate", () => {
  afterEach(() => {
    delete window.syrusShell
    resetBackendUpdateStoreForTests()
  })

  it("reports not-updating in a plain browser without window.syrusShell", () => {
    render(<Probe />)

    expect(screen.getByTestId("updating")).toHaveTextContent("false")
    expect(screen.getByTestId("phase")).toHaveTextContent("none")
  })

  it("reads an in-flight update from the bridge's initial snapshot", async () => {
    installBridge({ backendUpdate: { phase: "downloading", percent: 42 } })

    render(<Probe />)

    await waitFor(() => expect(screen.getByTestId("updating")).toHaveTextContent("true"))
    expect(screen.getByTestId("phase")).toHaveTextContent("downloading:42")
  })

  it("treats a missing backendUpdate member (older shells) as not-updating", async () => {
    const bridge = installBridge()
    const state = shellState()
    delete (state as Partial<SyrusShellState>).backendUpdate
    vi.mocked(bridge.getState).mockResolvedValue(state)

    render(<Probe />)

    await waitFor(() => expect(bridge.getState).toHaveBeenCalled())
    expect(screen.getByTestId("updating")).toHaveTextContent("false")
  })

  it("follows state-changed pushes through phases and back to not-updating", async () => {
    let pushState: ((state: SyrusShellState) => void) | undefined
    installBridge(
      {},
      {
        onStateChanged: vi.fn().mockImplementation((callback: (state: SyrusShellState) => void) => {
          pushState = callback
          return () => {}
        })
      }
    )

    render(<Probe />)
    await waitFor(() => expect(pushState).toBeDefined())

    act(() => pushState?.(shellState({ backendUpdate: { phase: "starting", percent: null } })))
    expect(screen.getByTestId("phase")).toHaveTextContent("starting:-")

    act(() => pushState?.(shellState({ backendUpdate: { phase: "migrating", percent: null } })))
    expect(screen.getByTestId("phase")).toHaveTextContent("migrating:-")

    act(() => pushState?.(shellState({ backendUpdate: null })))
    expect(screen.getByTestId("updating")).toHaveTextContent("false")
  })

  it("never lets the mount-time snapshot overwrite a fresher state-changed event", async () => {
    let resolveSnapshot: ((state: SyrusShellState) => void) | undefined
    let pushState: ((state: SyrusShellState) => void) | undefined
    installBridge(
      {},
      {
        getState: vi.fn().mockImplementation(
          () =>
            new Promise<SyrusShellState>((resolve) => {
              resolveSnapshot = resolve
            })
        ),
        onStateChanged: vi.fn().mockImplementation((callback: (state: SyrusShellState) => void) => {
          pushState = callback
          return () => {}
        })
      }
    )

    render(<Probe />)
    await waitFor(() => expect(pushState).toBeDefined())

    // The event arrives while getState is still in flight...
    act(() => pushState?.(shellState({ backendUpdate: { phase: "downloading", percent: 10 } })))
    expect(screen.getByTestId("phase")).toHaveTextContent("downloading:10")

    // ...then the stale snapshot resolves. It must not clobber the event.
    await act(async () => {
      resolveSnapshot?.(shellState({ backendUpdate: null }))
    })
    expect(screen.getByTestId("phase")).toHaveTextContent("downloading:10")
  })

  it("shares one bridge subscription across any number of consumers", async () => {
    const bridge = installBridge({ backendUpdate: { phase: "starting", percent: null } })

    render(
      <>
        <Probe />
        <Probe />
        <Probe />
      </>
    )

    await waitFor(() => expect(screen.getAllByTestId("updating")[0]).toHaveTextContent("true"))
    expect(bridge.onStateChanged).toHaveBeenCalledTimes(1)
    expect(bridge.getState).toHaveBeenCalledTimes(1)
  })
})
