import { act, fireEvent, render, screen } from "@testing-library/react"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import { ConnectRemote } from "./ConnectRemote"
import { analyzeInstanceUrl } from "./instanceUrl"

describe("analyzeInstanceUrl", () => {
  it("accepts a bare IP and assumes http plus Syrus's default port for the probe", () => {
    const analysis = analyzeInstanceUrl("192.168.4.21")
    expect(analysis.state).toBe("assumed")
    expect(analysis.normalized).toBe("http://192.168.4.21:3000")
    // No port lecture — production instances are https with no port at all.
    expect(analysis.hint).not.toContain("usually")
  })

  it("treats a partial IP as incomplete instead of previewing a mangled address", () => {
    // The WHATWG parser normalizes "192.168." to host 192.0.0.168 — a
    // confidently wrong preview while the user is still typing.
    for (const partial of ["192.168.", "192.168.64", "300.1.2.3", "192.168.64."]) {
      const analysis = analyzeInstanceUrl(partial)
      expect(analysis.state).toBe("invalid")
      expect(analysis.hint).toBe("Doesn't look like a server address yet.")
    }
  })

  it("accepts a bare IP with a port as-is", () => {
    const analysis = analyzeInstanceUrl("192.168.4.21:3000")
    expect(analysis.state).toBe("ready")
    expect(analysis.normalized).toBe("http://192.168.4.21:3000")
  })

  it("passes full https URLs through without port second-guessing", () => {
    const analysis = analyzeInstanceUrl("https://syrus.example.dev")
    expect(analysis.state).toBe("ready")
    expect(analysis.normalized).toBe("https://syrus.example.dev")
    expect(analysis.hint).not.toContain("3000")
  })

  it("honors explicit http without a port as typed, flagged as a caveat", () => {
    const analysis = analyzeInstanceUrl("http://192.168.64.1")
    expect(analysis.state).toBe("assumed")
    expect(analysis.normalized).toBe("http://192.168.64.1")
  })

  it("honors an explicitly typed :80 instead of rewriting it to :3000", () => {
    const analysis = analyzeInstanceUrl("syrus.internal:80")
    expect(analysis.state).toBe("ready")
    expect(analysis.normalized).toBe("http://syrus.internal")
    expect(analysis.hint).not.toContain("3000")
  })

  it("rejects paths, spaces, credentials, and non-http schemes with specific hints", () => {
    expect(analyzeInstanceUrl("http://host:3000/dashboard").hint).toContain("no path")
    expect(analyzeInstanceUrl("my server").hint).toContain("spaces")
    expect(analyzeInstanceUrl("http://user:pw@host:3000").hint).toContain("passwords")
    expect(analyzeInstanceUrl("ftp://host").hint).toContain("http://")
    expect(analyzeInstanceUrl("").state).toBe("empty")
  })
})

describe("ConnectRemote", () => {
  const stubProbe = (impl?: (request: { url: string }) => Promise<SyrusInstanceProbeResult>) => {
    const probeInstance = vi.fn(
      impl ?? (async () => ({ ok: true, url: "http://probed:3000", message: "" }))
    )
    ;(window as unknown as { syrusDesktop: unknown }).syrusDesktop = { probeInstance }
    return probeInstance
  }

  beforeEach(() => {
    vi.useFakeTimers()
  })

  afterEach(() => {
    vi.useRealTimers()
    vi.restoreAllMocks()
    delete (window as unknown as { syrusDesktop?: unknown }).syrusDesktop
  })

  it("submits only the address — there is no token field", () => {
    stubProbe()
    const onSubmit = vi.fn()
    render(<ConnectRemote error={null} busy={false} onSubmit={onSubmit} onBack={() => {}} />)

    expect(screen.queryByText(/API token/)).toBeNull()

    fireEvent.change(screen.getByLabelText(/Instance address/), { target: { value: "192.168.4.21" } })
    fireEvent.submit(screen.getByRole("button", { name: "Connect" }).closest("form")!)
    expect(onSubmit).toHaveBeenCalledWith("192.168.4.21")
  })

  it("shows a checking note first and only turns green when a Syrus actually answers", async () => {
    let resolveProbe: (value: SyrusInstanceProbeResult) => void = () => {}
    const probe = stubProbe(() => new Promise((resolve) => (resolveProbe = resolve)))
    render(<ConnectRemote error={null} busy={false} onSubmit={() => {}} onBack={() => {}} />)

    fireEvent.change(screen.getByLabelText(/Instance address/), { target: { value: "192.168.4.21" } })
    // Before the debounce fires: checking note, no green claim, no probe call.
    expect(screen.getByTestId("validation-hint").textContent).toContain("Checking http://192.168.4.21:3000")
    expect(probe).not.toHaveBeenCalled()

    await act(async () => {
      vi.advanceTimersByTime(700)
    })
    expect(probe).toHaveBeenCalledWith({ url: "192.168.4.21" })

    await act(async () => {
      resolveProbe({ ok: true, url: "http://192.168.4.21:3000", message: "" })
    })
    expect(screen.getByTestId("validation-hint").textContent).toContain("Syrus found at http://192.168.4.21:3000")
  })

  it("shows the classified failure when nothing answers, without blocking submit", async () => {
    stubProbe(async () => ({ ok: false, url: "http://192.168.64.1:3", message: "Nothing answered at http://192.168.64.1:3." }))
    render(<ConnectRemote error={null} busy={false} onSubmit={() => {}} onBack={() => {}} />)

    fireEvent.change(screen.getByLabelText(/Instance address/), { target: { value: "192.168.64.1:3" } })
    await act(async () => {
      vi.advanceTimersByTime(700)
    })

    expect(screen.getByTestId("validation-hint").textContent).toContain("Nothing answered")
    // The probe is advisory: Connect stays enabled for a parseable address.
    expect((screen.getByRole("button", { name: "Connect" }) as HTMLButtonElement).disabled).toBe(false)
  })

  it("discards stale probe results when the user keeps typing", async () => {
    const resolvers: Array<(value: SyrusInstanceProbeResult) => void> = []
    stubProbe(() => new Promise((resolve) => resolvers.push(resolve)))
    render(<ConnectRemote error={null} busy={false} onSubmit={() => {}} onBack={() => {}} />)

    const input = screen.getByLabelText(/Instance address/)
    fireEvent.change(input, { target: { value: "192.168.4.21" } })
    await act(async () => {
      vi.advanceTimersByTime(700)
    })
    fireEvent.change(input, { target: { value: "192.168.4.22" } })
    await act(async () => {
      vi.advanceTimersByTime(700)
    })

    // The FIRST probe resolving late must not paint a green check for the
    // old address.
    await act(async () => {
      resolvers[0]({ ok: true, url: "http://192.168.4.21:3000", message: "" })
    })
    expect(screen.getByTestId("validation-hint").textContent).not.toContain("192.168.4.21:3000")

    await act(async () => {
      resolvers[1]({ ok: true, url: "http://192.168.4.22:3000", message: "" })
    })
    expect(screen.getByTestId("validation-hint").textContent).toContain("Syrus found at http://192.168.4.22:3000")
  })

  it("shows amber incomplete guidance while typing a partial IP", () => {
    stubProbe()
    render(<ConnectRemote error={null} busy={false} onSubmit={() => {}} onBack={() => {}} />)

    fireEvent.change(screen.getByLabelText(/Instance address/), { target: { value: "192.168." } })
    expect(screen.getByTestId("validation-hint").textContent).toContain("Doesn't look like a server address yet")
    expect((screen.getByRole("button", { name: "Connect" }) as HTMLButtonElement).disabled).toBe(true)
  })

  it("renders server errors with role=alert and keeps Back usable while busy", () => {
    stubProbe()
    const onBack = vi.fn()
    const { rerender } = render(
      <ConnectRemote error="Nothing answered at http://x:3000." busy={false} onSubmit={() => {}} onBack={onBack} />
    )
    expect(screen.getByRole("alert").textContent).toContain("Nothing answered")

    rerender(<ConnectRemote error={null} busy checkingUrl="http://x:3000" onSubmit={() => {}} onBack={onBack} />)
    // A black-holed host must never be a dead end.
    fireEvent.click(screen.getByRole("button", { name: "Back" }))
    expect(onBack).toHaveBeenCalled()
  })
})
