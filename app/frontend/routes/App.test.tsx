import { render, screen } from "@testing-library/react"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"
import { describe, expect, it, vi } from "vitest"
import { MemoryRouter } from "react-router-dom"
import { App } from "./App"

const actionCable = vi.hoisted(() => ({
  createSubscription: vi.fn(() => ({ unsubscribe: vi.fn() }))
}))

vi.mock("@rails/actioncable", () => ({
  createConsumer: () => ({
    subscriptions: {
      create: actionCable.createSubscription
    }
  })
}))

describe("App", () => {
  it("loads bootstrap data into the SPA shell", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockResolvedValue(
      new Response(
        JSON.stringify({
          current_user: {
            id: 1,
            email_address: "operator@example.com",
            name: "Operator",
            display_name: "Operator",
            admin: true,
            scheduling_paused: false,
            landing_paused: false,
            agent_provider: "claude",
            agent_max_turns: 200
          },
          app: {
            revision: "dev",
            revision_url: null
          },
          csrf_token: "csrf-token",
          feature_flags: {
            migrated_routes: []
          }
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      )
    )

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(screen.getByRole("main", { name: "Syrus SPA" })).toBeInTheDocument()
    expect(await screen.findByText("Operator")).toBeInTheDocument()
    expect(screen.getByText("operator@example.com")).toBeInTheDocument()
    expect(screen.getByText("dev")).toBeInTheDocument()
    expect(fetchSpy).toHaveBeenCalledWith(
      "/api/v1/app/bootstrap",
      expect.objectContaining({
        credentials: "same-origin",
        headers: { Accept: "application/json" }
      })
    )
    expect(actionCable.createSubscription).toHaveBeenCalledWith(
      { channel: "AppUserChannel" },
      expect.objectContaining({ received: expect.any(Function) })
    )
  })

  it("renders the admin overview route from the app admin API", async () => {
    vi.spyOn(window, "fetch").mockResolvedValue(
      new Response(
        JSON.stringify({
          active_runs: { total: 2, by_trigger: { initial: 1, retry: 1 } },
          queued_runs: { total: 1 },
          recent_failures_24h: { total: 0, by_trigger: {} },
          github_rate_limits: [],
          github_api_blocked_users: [],
          agent_session_capture_rate: { total: 3, captured: 3, rate: 1.0 },
          workers: { total: 1, stale: 0 },
          recurring: { overdue: [] },
          stuck: [
            {
              kind: "stale_heartbeat",
              severity: "warn",
              detail: "Run #4 silent for 10m",
              age_label: "10m",
              run_id: 4,
              workflow_id: 2,
              job_id: 1
            }
          ]
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      )
    )

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/admin"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(await screen.findByText("Active runs")).toBeInTheDocument()
    expect(screen.getByRole("main", { name: "Admin overview" })).toBeInTheDocument()
    expect(screen.getByRole("link", { name: /Active runs/ })).toHaveAttribute("href", "/admin/queue/active")
    expect(screen.getByText("2")).toBeInTheDocument()
    expect(screen.getByText("Run #4 silent for 10m")).toBeInTheDocument()
  })

  it("renders the migrated /admin route from the same admin overview component", async () => {
    vi.spyOn(window, "fetch").mockResolvedValue(
      new Response(
        JSON.stringify({
          active_runs: { total: 0, by_trigger: {} },
          queued_runs: { total: 0 },
          recent_failures_24h: { total: 0, by_trigger: {} },
          github_rate_limits: [],
          github_api_blocked_users: [],
          agent_session_capture_rate: { total: 0, captured: 0, rate: null },
          workers: { total: 1, stale: 0 },
          recurring: { overdue: [] },
          stuck: []
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      )
    )

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/admin"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(await screen.findByText("GitHub rate limits")).toBeInTheDocument()
    expect(screen.getByRole("main", { name: "Admin overview" })).toBeInTheDocument()
  })

  it("renders the admin queue route from the app admin queue API", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockResolvedValue(
      new Response(
        JSON.stringify({
          jobs: [
            {
              id: 12,
              class_name: "RunJob",
              queue_name: "runs",
              arguments: [42],
              created_at: "2026-05-30T12:00:00Z",
              claimed_at: "2026-05-30T12:01:00Z"
            }
          ]
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      )
    )

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/admin/queue/active"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(screen.getByRole("main", { name: "Admin queue" })).toBeInTheDocument()
    expect(await screen.findByText("RunJob")).toBeInTheDocument()
    expect(screen.getByText("runs")).toBeInTheDocument()
    expect(screen.getByRole("link", { name: "Failed" })).toHaveAttribute("href", "/app-shell/admin/queue/failed")
    expect(fetchSpy).toHaveBeenCalledWith(
      "/api/v1/app/admin/queue/active",
      expect.objectContaining({
        credentials: "same-origin",
        headers: { Accept: "application/json" }
      })
    )
  })
})
