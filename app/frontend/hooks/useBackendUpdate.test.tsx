import { act, render, screen, waitFor } from "@testing-library/react"
import { afterEach, describe, expect, it, vi } from "vitest"
import type { SyrusBackendUpdate, SyrusShellBridge, SyrusShellState } from "../lib/desktopShell"
import {
  BACKEND_UPDATE_STALE_MS,
  backendUpdateListenerCountForTests,
  resetBackendUpdateStoreForTests,
  useBackendOutage,
  useBackendUpdate
} from "./useBackendUpdate"

function backendUpdate(overrides: Partial<SyrusBackendUpdate> = {}): SyrusBackendUpdate {
  return { phase: "starting", percent: null, outage: false, ...overrides }
}

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
  const outage = useBackendOutage()
  return (
    <div>
      <span data-testid="outage">{String(outage)}</span>
      <span data-testid="phase">{update ? `${update.phase}:${update.percent ?? "-"}:${String(update.outage)}` : "none"}</span>
    </div>
  )
}

describe("useBackendUpdate", () => {
  afterEach(() => {
    delete window.syrusShell
    resetBackendUpdateStoreForTests()
    vi.useRealTimers()
  })

  it("reports no update and no outage in a plain browser without window.syrusShell", () => {
    render(<Probe />)

    expect(screen.getByTestId("outage")).toHaveTextContent("false")
    expect(screen.getByTestId("phase")).toHaveTextContent("none")
  })

  it("reads an in-flight update from the bridge's initial snapshot", async () => {
    installBridge({ backendUpdate: backendUpdate({ phase: "downloading", percent: 42 }) })

    render(<Probe />)

    await waitFor(() => expect(screen.getByTestId("phase")).toHaveTextContent("downloading:42:false"))
    // A pull is not an outage — the old backend still serves requests.
    expect(screen.getByTestId("outage")).toHaveTextContent("false")
  })

  it("reports an outage only when the update has actually taken the backend down", async () => {
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

    act(() => pushState?.(shellState({ backendUpdate: backendUpdate({ phase: "downloading", percent: 80 }) })))
    expect(screen.getByTestId("outage")).toHaveTextContent("false")

    act(() => pushState?.(shellState({ backendUpdate: backendUpdate({ phase: "migrating", outage: true }) })))
    expect(screen.getByTestId("outage")).toHaveTextContent("true")

    act(() => pushState?.(shellState({ backendUpdate: null })))
    expect(screen.getByTestId("outage")).toHaveTextContent("false")
    expect(screen.getByTestId("phase")).toHaveTextContent("none")
  })

  it("treats a missing backendUpdate member (older shells) as not-updating", async () => {
    const bridge = installBridge()
    const state = shellState()
    delete (state as Partial<SyrusShellState>).backendUpdate
    vi.mocked(bridge.getState).mockResolvedValue(state)

    render(<Probe />)

    await waitFor(() => expect(bridge.getState).toHaveBeenCalled())
    expect(screen.getByTestId("outage")).toHaveTextContent("false")
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
    act(() => pushState?.(shellState({ backendUpdate: backendUpdate({ phase: "downloading", percent: 10 }) })))
    expect(screen.getByTestId("phase")).toHaveTextContent("downloading:10:false")

    // ...then the stale snapshot resolves. It must not clobber the event.
    await act(async () => {
      resolveSnapshot?.(shellState({ backendUpdate: null }))
    })
    expect(screen.getByTestId("phase")).toHaveTextContent("downloading:10:false")
  })

  it("drops a stale update when the bridge goes silent — gating must not stick forever", async () => {
    // A shell whose update wedged (or died) without ever clearing the state
    // would otherwise suppress readiness warnings indefinitely. Fresh events
    // re-arm the fuse; silence past the bound clears the snapshot.
    vi.useFakeTimers()
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
    await act(async () => {
      await vi.advanceTimersByTimeAsync(0)
    })

    act(() => pushState?.(shellState({ backendUpdate: backendUpdate({ phase: "migrating", outage: true }) })))
    expect(screen.getByTestId("outage")).toHaveTextContent("true")

    // A fresh event just before the bound re-arms the fuse...
    act(() => vi.advanceTimersByTime(BACKEND_UPDATE_STALE_MS - 1000))
    act(() => pushState?.(shellState({ backendUpdate: backendUpdate({ phase: "migrating", percent: null, outage: true }) })))
    act(() => vi.advanceTimersByTime(BACKEND_UPDATE_STALE_MS - 1000))
    expect(screen.getByTestId("outage")).toHaveTextContent("true")

    // ...but full silence past the bound stops the gating.
    act(() => vi.advanceTimersByTime(2000))
    expect(screen.getByTestId("outage")).toHaveTextContent("false")
    expect(screen.getByTestId("phase")).toHaveTextContent("none")
  })

  it("shares one bridge subscription across any number of consumers", async () => {
    const bridge = installBridge({ backendUpdate: backendUpdate({ outage: true }) })

    render(
      <>
        <Probe />
        <Probe />
        <Probe />
      </>
    )

    await waitFor(() => expect(screen.getAllByTestId("outage")[0]).toHaveTextContent("true"))
    expect(bridge.onStateChanged).toHaveBeenCalledTimes(1)
    expect(bridge.getState).toHaveBeenCalledTimes(1)
  })

  it("removes its store listener on unmount", async () => {
    const bridge = installBridge()

    const first = render(<Probe />)
    const second = render(<Probe />)
    await waitFor(() => expect(bridge.getState).toHaveBeenCalled())
    // Two mounted Probes × two hooks each.
    expect(backendUpdateListenerCountForTests()).toBe(4)

    first.unmount()
    expect(backendUpdateListenerCountForTests()).toBe(2)

    second.unmount()
    expect(backendUpdateListenerCountForTests()).toBe(0)
  })
})
