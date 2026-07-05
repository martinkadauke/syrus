import { fireEvent, render, screen } from "@testing-library/react"
import { afterEach, describe, expect, it, vi } from "vitest"
import { ConnectRemote } from "./ConnectRemote"
import { analyzeInstanceUrl } from "./instanceUrl"

describe("analyzeInstanceUrl", () => {
  it("accepts a bare IP and assumes http plus Syrus's default port", () => {
    const analysis = analyzeInstanceUrl("192.168.4.21")
    expect(analysis.state).toBe("assumed")
    expect(analysis.normalized).toBe("http://192.168.4.21:3000")
    expect(analysis.hint).toContain("port 3000")
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

  it("suggests the port may be missing on explicit http without one", () => {
    const analysis = analyzeInstanceUrl("http://192.168.64.1")
    expect(analysis.state).toBe("ready")
    expect(analysis.normalized).toBe("http://192.168.64.1")
    expect(analysis.hint).toContain(":3000")
  })

  it("rejects paths, spaces, credentials, and non-http schemes with specific hints", () => {
    expect(analyzeInstanceUrl("http://host:3000/dashboard").hint).toContain("no path")
    expect(analyzeInstanceUrl("my server").hint).toContain("spaces")
    expect(analyzeInstanceUrl("http://user:pw@host:3000").hint).toContain("passwords")
    expect(analyzeInstanceUrl("ftp://host").hint).toContain("http://")
    expect(analyzeInstanceUrl("").state).toBe("empty")
  })

  it("strips trailing slashes via URL origin", () => {
    expect(analyzeInstanceUrl("https://syrus.example.dev/").normalized).toBe("https://syrus.example.dev")
  })
})

describe("ConnectRemote", () => {
  afterEach(() => {
    vi.restoreAllMocks()
  })

  it("submits only the address — there is no token field", () => {
    const onSubmit = vi.fn()
    render(<ConnectRemote error={null} busy={false} onSubmit={onSubmit} onBack={() => {}} />)

    expect(screen.queryByText(/API token/)).toBeNull()

    fireEvent.change(screen.getByLabelText(/Instance address/), { target: { value: "192.168.4.21" } })
    fireEvent.submit(screen.getByRole("button", { name: "Connect" }).closest("form")!)
    expect(onSubmit).toHaveBeenCalledWith("192.168.4.21")
  })

  it("previews the normalized address while typing", () => {
    render(<ConnectRemote error={null} busy={false} onSubmit={() => {}} onBack={() => {}} />)

    fireEvent.change(screen.getByLabelText(/Instance address/), { target: { value: "192.168.4.21" } })
    expect(screen.getByTestId("validation-hint").textContent).toContain("http://192.168.4.21:3000")
  })

  it("shows amber guidance and disables Connect for an invalid address", () => {
    render(<ConnectRemote error={null} busy={false} onSubmit={() => {}} onBack={() => {}} />)

    fireEvent.change(screen.getByLabelText(/Instance address/), { target: { value: "not a url" } })
    expect(screen.getByTestId("validation-hint").textContent).toContain("spaces")
    expect((screen.getByRole("button", { name: "Connect" }) as HTMLButtonElement).disabled).toBe(true)
  })

  it("renders server errors with role=alert and keeps Back usable while busy", () => {
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
