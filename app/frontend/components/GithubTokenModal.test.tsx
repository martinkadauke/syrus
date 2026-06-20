import { fireEvent, render, screen, waitFor } from "@testing-library/react"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"
import { afterEach, describe, expect, it, vi } from "vitest"
import { GithubTokenModal } from "./GithubTokenModal"

function renderModal(props: { onClose?: () => void; onSaved?: () => void } = {}) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(
    <QueryClientProvider client={client}>
      <GithubTokenModal onClose={props.onClose ?? (() => {})} onSaved={props.onSaved} />
    </QueryClientProvider>
  )
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } })
}

// Route fetch by the path the api client hits.
function mockRoutes(routes: { test?: () => Response; save?: () => Response }) {
  return vi.spyOn(window, "fetch").mockImplementation(async (input) => {
    const url = String(input)
    if (url.endsWith("/test_github_token")) return routes.test?.() ?? jsonResponse({ credential_test: { ok: false, message: "", details: {} } })
    if (url.endsWith("/credentials")) return routes.save?.() ?? jsonResponse({})
    throw new Error(`unexpected fetch: ${url}`)
  })
}

const okResult = { credential: "github_token", ok: true, message: "Token is valid for octocat.", details: { login: "octocat", scopes: ["repo", "workflow"], missing_scopes: [] } }

describe("GithubTokenModal", () => {
  afterEach(() => {
    vi.restoreAllMocks()
  })

  it("links to GitHub settings and advises classic token, no expiration, repo + workflow scopes", () => {
    renderModal()

    const link = screen.getByRole("link", { name: /Open github.com\/settings\/tokens/ })
    expect(link).toHaveAttribute("href", "https://github.com/settings/tokens")
    expect(link).toHaveAttribute("target", "_blank")
    expect(screen.getByText(/No expiration/)).toBeInTheDocument()
    expect(screen.getByText("repo")).toBeInTheDocument()
    expect(screen.getByText("workflow")).toBeInTheDocument()
  })

  it("tests the token on paste and shows a green check, enabling save", async () => {
    mockRoutes({ test: () => jsonResponse({ credential_test: okResult }) })
    renderModal()

    expect(screen.getByRole("button", { name: "Save and continue" })).toBeDisabled()
    fireEvent.change(screen.getByPlaceholderText("ghp_…"), { target: { value: "ghp_good" } })

    await waitFor(() => expect(screen.getByText("Token is valid for octocat.")).toBeInTheDocument())
    expect(screen.getByRole("button", { name: "Save and continue" })).toBeEnabled()
  })

  it("warns and blocks save when a required scope is missing", async () => {
    const underScoped = {
      credential: "github_token",
      ok: false,
      message: "Token authenticated as octocat, but it is missing the workflow scope. Regenerate a classic token with repo and workflow enabled.",
      details: { login: "octocat", scopes: ["repo"], missing_scopes: ["workflow"] }
    }
    mockRoutes({ test: () => jsonResponse({ credential_test: underScoped }) })
    renderModal()

    fireEvent.change(screen.getByPlaceholderText("ghp_…"), { target: { value: "ghp_partial" } })

    await waitFor(() => expect(screen.getByText(/missing the workflow scope/)).toBeInTheDocument())
    expect(screen.getByRole("button", { name: "Save and continue" })).toBeDisabled()
  })

  it("shows an error and blocks save when GitHub rejects the token", async () => {
    const rejected = { credential: "github_token", ok: false, message: "GitHub rejected this token. Check that you copied the whole value.", details: {} }
    mockRoutes({ test: () => jsonResponse({ credential_test: rejected }) })
    renderModal()

    fireEvent.change(screen.getByPlaceholderText("ghp_…"), { target: { value: "nope" } })

    await waitFor(() => expect(screen.getByText(/GitHub rejected this token/)).toBeInTheDocument())
    expect(screen.getByRole("button", { name: "Save and continue" })).toBeDisabled()
  })

  it("PATCHes only the github token after a valid test, then closes and signals saved", async () => {
    const fetchSpy = mockRoutes({
      test: () => jsonResponse({ credential_test: okResult }),
      save: () => jsonResponse({ message: "Credentials updated." })
    })
    const onClose = vi.fn()
    const onSaved = vi.fn()
    renderModal({ onClose, onSaved })

    fireEvent.change(screen.getByPlaceholderText("ghp_…"), { target: { value: "ghp_good" } })
    await waitFor(() => expect(screen.getByRole("button", { name: "Save and continue" })).toBeEnabled())
    fireEvent.click(screen.getByRole("button", { name: "Save and continue" }))

    await waitFor(() => expect(onClose).toHaveBeenCalledTimes(1))
    expect(onSaved).toHaveBeenCalledTimes(1)

    const saveCall = fetchSpy.mock.calls.find(([url]) => String(url).endsWith("/credentials"))
    expect(saveCall).toBeDefined()
    expect(saveCall?.[1]?.method).toBe("PATCH")
    expect(JSON.parse(saveCall?.[1]?.body as string)).toEqual({ user: { github_token: "ghp_good" } })
  })

  it("shows GitHub App + PAT tabs for admins, defaulting to the App tab", async () => {
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
    client.setQueryData(["bootstrap"], { current_user: { admin: true } })
    vi.spyOn(window, "fetch").mockImplementation(async (input) => {
      const url = String(input)
      if (url.endsWith("/admin/github_app/register")) {
        return jsonResponse({
          github_app: { registered: false, id: null, slug: null, registered_at: null, install_url: null },
          github_manifest_url: "https://github.com/settings/apps/new?state=abc",
          manifest: "{}",
          submit_label: "Register GitHub App"
        })
      }
      if (url.endsWith("/admin/github_app/confirm")) return jsonResponse({ github_app: { registered: false, id: null, slug: null, registered_at: null, install_url: null } })
      if (url.endsWith("/api/v1/app/bootstrap")) return jsonResponse({ current_user: { admin: true } })
      return jsonResponse({})
    })

    render(
      <QueryClientProvider client={client}>
        <GithubTokenModal onClose={() => {}} />
      </QueryClientProvider>
    )

    expect(await screen.findByRole("tab", { name: /GitHub App/ })).toHaveAttribute("aria-selected", "true")
    expect(screen.getByRole("tab", { name: "Personal access token" })).toBeInTheDocument()
    // App tab is active: the manifest register button shows, not the PAT field.
    expect(await screen.findByRole("button", { name: /Register GitHub App/ })).toBeInTheDocument()
    expect(screen.queryByPlaceholderText("ghp_…")).not.toBeInTheDocument()

    // Switching to the PAT tab reveals the token field.
    fireEvent.click(screen.getByRole("tab", { name: "Personal access token" }))
    expect(screen.getByPlaceholderText("ghp_…")).toBeInTheDocument()
  })
})
