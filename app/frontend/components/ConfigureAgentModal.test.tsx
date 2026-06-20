import { fireEvent, render, screen, waitFor } from "@testing-library/react"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"
import { afterEach, describe, expect, it, vi } from "vitest"
import { ConfigureAgentModal } from "./ConfigureAgentModal"

function renderModal(props: { onClose?: () => void; onSaved?: () => void } = {}) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(
    <QueryClientProvider client={client}>
      <ConfigureAgentModal onClose={props.onClose ?? (() => {})} onSaved={props.onSaved} />
    </QueryClientProvider>
  )
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } })
}

const notReady = { credential: "claude_oauth_token", ok: false, message: "Claude is not authenticated on this machine yet.", details: {} }
const ready = { credential: "claude_oauth_token", ok: true, message: "Claude already works on this machine — no token needed.", details: {} }

function mockRoutes(routes: { preflight?: () => Response; start?: () => Response; creds?: () => Response }) {
  return vi.spyOn(window, "fetch").mockImplementation(async (input) => {
    const url = String(input)
    if (url.endsWith("/test_claude_cli")) return routes.preflight?.() ?? jsonResponse({ credential_test: notReady })
    if (url.endsWith("/claude_oauth_start")) return routes.start?.() ?? jsonResponse({ authorize_url: "https://claude.ai/oauth/authorize?x=1" })
    if (url.endsWith("/api/v1/app/credentials")) return routes.creds?.() ?? jsonResponse({ credential_status: { claude_oauth_token: false } })
    throw new Error(`unexpected fetch: ${url}`)
  })
}

describe("ConfigureAgentModal", () => {
  afterEach(() => {
    vi.restoreAllMocks()
  })

  it("shows a Claude tab and a disabled Codex tab", async () => {
    mockRoutes({})
    renderModal()

    expect(screen.getByRole("tab", { name: "Claude" })).toHaveAttribute("aria-selected", "true")
    const codex = screen.getByRole("tab", { name: /Codex/ })
    expect(codex).toBeDisabled()
    await waitFor(() => expect(window.fetch).toHaveBeenCalled())
  })

  it("preflights and reassures when Claude already works on this machine", async () => {
    mockRoutes({ preflight: () => jsonResponse({ credential_test: ready }) })
    renderModal()

    await waitFor(() => expect(screen.getByText(/already works on this machine/)).toBeInTheDocument())
    // Cancel reads as "Skip for now" once ambient Claude is confirmed.
    expect(screen.getByRole("button", { name: "Skip for now" })).toBeInTheDocument()
  })

  it("opens the authorize URL in a popup when authorizing", async () => {
    const openSpy = vi.spyOn(window, "open").mockReturnValue({} as Window)
    mockRoutes({ start: () => jsonResponse({ authorize_url: "https://claude.ai/oauth/authorize?state=abc" }) })
    renderModal()

    await waitFor(() => expect(screen.queryByText(/Checking for an existing Claude login/)).not.toBeInTheDocument())
    fireEvent.click(screen.getByRole("button", { name: "Authorize with Claude" }))

    await waitFor(() => expect(openSpy).toHaveBeenCalledWith("https://claude.ai/oauth/authorize?state=abc", "syrus-claude-oauth", expect.any(String)))
    expect(screen.getByText(/Waiting for approval/)).toBeInTheDocument()
  })

  it("completes when the callback window posts a success message", async () => {
    vi.spyOn(window, "open").mockReturnValue({} as Window)
    mockRoutes({})
    const onSaved = vi.fn()
    renderModal({ onSaved })

    await waitFor(() => expect(screen.getByRole("button", { name: "Authorize with Claude" })).toBeInTheDocument())
    fireEvent.click(screen.getByRole("button", { name: "Authorize with Claude" }))
    await waitFor(() => expect(screen.getByText(/Waiting for approval/)).toBeInTheDocument())

    window.dispatchEvent(new MessageEvent("message", {
      origin: window.location.origin,
      data: { type: "syrus:claude-oauth", ok: true, message: "Claude OAuth token is valid." }
    }))

    await waitFor(() => expect(screen.getByText("Claude OAuth token is valid.")).toBeInTheDocument())
    expect(onSaved).toHaveBeenCalledTimes(1)
    expect(screen.getByRole("button", { name: "Done" })).toBeInTheDocument()
  })

  it("surfaces a failure message from the callback window", async () => {
    vi.spyOn(window, "open").mockReturnValue({} as Window)
    mockRoutes({})
    renderModal()

    await waitFor(() => expect(screen.getByRole("button", { name: "Authorize with Claude" })).toBeInTheDocument())
    fireEvent.click(screen.getByRole("button", { name: "Authorize with Claude" }))
    await waitFor(() => expect(screen.getByText(/Waiting for approval/)).toBeInTheDocument())

    window.dispatchEvent(new MessageEvent("message", {
      origin: window.location.origin,
      data: { type: "syrus:claude-oauth", ok: false, message: "GitHub rejected this token." }
    }))

    await waitFor(() => expect(screen.getByText("GitHub rejected this token.")).toBeInTheDocument())
  })
})
