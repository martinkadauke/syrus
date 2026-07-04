import { fireEvent, render, screen, waitFor } from "@testing-library/react"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"
import { afterEach, describe, expect, it, vi } from "vitest"
import { GithubAppPanel } from "./GithubAppPanel"

function renderPanel(props: { onClose?: () => void; onSaved?: () => void } = {}) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(
    <QueryClientProvider client={client}>
      <GithubAppPanel onClose={props.onClose ?? (() => {})} onSaved={props.onSaved} />
    </QueryClientProvider>
  )
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } })
}

const notRegistered = { registered: false, id: null, slug: null, registered_at: null, install_url: null }
const registered = { registered: true, id: 42, slug: "operator-syrus", registered_at: "2026-06-20T00:00:00Z", install_url: "https://github.com/apps/operator-syrus/installations/new" }
const bounceUrl = "http://localhost:3000/admin/github_app/manifest?state=abc&syrus_external=1"

function mockRoutes(over: { register?: () => Response; confirm?: () => Response } = {}) {
  return vi.spyOn(window, "fetch").mockImplementation(async (input) => {
    const url = String(input)
    if (url.includes("/admin/github_app/register")) {
      return over.register?.() ?? jsonResponse({
        github_app: notRegistered,
        bounce_url: bounceUrl,
        submit_label: "Register GitHub App"
      })
    }
    if (url.endsWith("/admin/github_app/confirm")) return over.confirm?.() ?? jsonResponse({ github_app: notRegistered })
    throw new Error(`unexpected fetch: ${url}`)
  })
}

describe("GithubAppPanel", () => {
  afterEach(() => {
    vi.restoreAllMocks()
  })

  it("renders the registration button when the App is not registered", async () => {
    mockRoutes()
    renderPanel()

    await screen.findByRole("button", { name: /Register GitHub App/ })
    expect(screen.getByText("The GitHub App enables actions to appear as a bot natively on your repositories.")).toBeInTheDocument()
    expect(screen.queryByText(/recommended credential/)).not.toBeInTheDocument()
  })

  it("shows a clean success state once registered — installation happens at add-repository time", async () => {
    mockRoutes({ register: () => jsonResponse({ github_app: registered, bounce_url: bounceUrl, submit_label: "Re-register GitHub App" }), confirm: () => jsonResponse({ github_app: registered }) })
    const onSaved = vi.fn()
    renderPanel({ onSaved })

    expect(await screen.findByText("The Syrus GitHub App is registered.")).toBeInTheDocument()
    expect(screen.getByText(/connect it to repositories as you add them/)).toBeInTheDocument()
    expect(screen.getByRole("button", { name: "Done" })).toBeInTheDocument()
    // No install-on-repositories homework here: the pre-scoped install link
    // is offered by the add-repository flow, where it's actionable.
    expect(screen.queryByRole("link", { name: /Install the Syrus App/ })).not.toBeInTheDocument()
    await waitFor(() => expect(onSaved).toHaveBeenCalled())
  })

  it("falls back to a note when the user is not an admin (403)", async () => {
    mockRoutes({ register: () => jsonResponse({ error: { message: "Admin access required." } }, 403) })
    renderPanel()

    await waitFor(() => expect(screen.getByText(/Only an admin can register/)).toBeInTheDocument())
  })

  it("opens the bounce page in a new tab and starts polling", async () => {
    const fetchSpy = mockRoutes()
    const opened = { opener: {} as unknown }
    const openSpy = vi.spyOn(window, "open").mockReturnValue(opened as Window)
    renderPanel()

    fireEvent.click(await screen.findByRole("button", { name: /Register GitHub App/ }))

    expect(openSpy).toHaveBeenCalledWith(bounceUrl, "_blank")
    expect(opened.opener).toBeNull()
    await waitFor(() => expect(screen.getByText(/Waiting for GitHub to finish/)).toBeInTheDocument())
    expect(screen.queryByText(/Popup blocked/)).not.toBeInTheDocument()
    expect(fetchSpy).toHaveBeenCalled()
  })

  it("offers a manual link when the popup is blocked in a plain browser", async () => {
    mockRoutes()
    vi.spyOn(window, "open").mockReturnValue(null)
    renderPanel()

    fireEvent.click(await screen.findByRole("button", { name: /Register GitHub App/ }))

    const manual = await screen.findByRole("link", { name: /Open the registration page/ })
    expect(manual).toHaveAttribute("href", bounceUrl)
  })

  it("treats a null window.open as success inside the desktop shell", async () => {
    mockRoutes()
    vi.spyOn(window, "open").mockReturnValue(null)
    vi.spyOn(navigator, "userAgent", "get").mockReturnValue("Mozilla/5.0 Electron/39.0.0 SyrusDesktop/0.1.0")
    renderPanel()

    fireEvent.click(await screen.findByRole("button", { name: /Register GitHub App/ }))

    await waitFor(() => expect(screen.getByText(/Waiting for GitHub to finish/)).toBeInTheDocument())
    expect(screen.queryByText(/Popup blocked/)).not.toBeInTheDocument()
  })
})
