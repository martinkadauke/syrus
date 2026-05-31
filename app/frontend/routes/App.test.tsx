import { fireEvent, render, screen, waitFor, within } from "@testing-library/react"
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

vi.mock("@excalidraw/excalidraw", () => ({
  Excalidraw: ({ excalidrawAPI, initialData, onChange }: {
    excalidrawAPI?: (api: { updateScene: () => void }) => void
    initialData?: { elements?: unknown[] }
    onChange?: (elements: unknown[]) => void
  }) => {
    excalidrawAPI?.({ updateScene: () => {} })

    return (
      <button
        onClick={() => onChange?.([...(initialData?.elements || []), { id: "shape-react", version: 1 }])}
        type="button"
      >
        Draw on whiteboard
      </button>
    )
  }
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

  it("renders shared app chrome from embedded bootstrap data", async () => {
    const script = document.createElement("script")
    script.id = "syrus-bootstrap-data"
    script.type = "application/json"
    script.textContent = JSON.stringify(bootstrapPayload())
    document.body.appendChild(script)
    const fetchSpy = vi.spyOn(window, "fetch").mockRejectedValue(new Error("unexpected fetch"))

    try {
      render(
        <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
          <MemoryRouter initialEntries={["/app-shell"]}>
            <App />
          </MemoryRouter>
        </QueryClientProvider>
      )

      expect(await screen.findByRole("navigation", { name: "Primary" })).toBeInTheDocument()
      expect(screen.getByRole("link", { name: "Dashboard" })).toHaveAttribute("href", "/app-shell/dashboard/jobs?view=list")
      expect(screen.getByRole("link", { name: "Admin" })).toHaveAttribute("href", "/app-shell/admin")
      expect(screen.getAllByText("Operator").length).toBeGreaterThan(0)
      expect(screen.getAllByText("dev").length).toBeGreaterThan(0)
      expect(fetchSpy).not.toHaveBeenCalled()
    } finally {
      script.remove()
    }
  })

  it("submits bug reports from the shared app chrome", async () => {
    const script = document.createElement("script")
    script.id = "syrus-bootstrap-data"
    script.type = "application/json"
    script.textContent = JSON.stringify(bootstrapPayload())
    document.body.appendChild(script)
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input, init) => {
      const path = String(input)
      if (path === "/api/v1/app/bug_reports" && init?.method === "POST") {
        return Promise.resolve(new Response(JSON.stringify({ message: "Bug report queued.", job_id: 44 }), { status: 201, headers: { "Content-Type": "application/json" } }))
      }

      return Promise.reject(new Error(`Unexpected fetch: ${path}`))
    })

    try {
      render(
        <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
          <MemoryRouter initialEntries={["/app-shell"]}>
            <App />
          </MemoryRouter>
        </QueryClientProvider>
      )

      fireEvent.click(await screen.findByRole("button", { name: "Report a bug" }))
      expect(screen.getByRole("dialog", { name: "Report a bug" })).toBeInTheDocument()
      expect(screen.getByLabelText("Title")).toHaveValue("Dashboard bug")
      fireEvent.change(screen.getByLabelText("Description"), { target: { value: "The aqueduct counter is off by one." } })
      fireEvent.click(screen.getByRole("button", { name: "Create Job" }))

      await waitFor(() => {
        expect(fetchSpy).toHaveBeenCalledWith(
          "/api/v1/app/bug_reports",
          expect.objectContaining({ method: "POST", credentials: "same-origin", body: expect.any(FormData) })
        )
      })
      const form = fetchSpy.mock.calls[0]?.[1]?.body as FormData
      expect(form.get("title")).toBe("Dashboard bug")
      expect(form.get("description")).toBe("The aqueduct counter is off by one.")
      expect(await screen.findByRole("status")).toHaveTextContent("Bug report queued.")
      expect(screen.queryByRole("dialog", { name: "Report a bug" })).not.toBeInTheDocument()
    } finally {
      script.remove()
    }
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
    expect(screen.getByRole("link", { name: /Stuck things/ })).toHaveAttribute("href", "/admin/stuck")
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

  it("renders the app-shell dashboard route from the app dashboard API", async () => {
    let sortColumn = "created_at"
    let sortDirection = "desc"
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input, init) => {
      const path = String(input)
      if (path === "/api/v1/app/dashboard/preferences" && init?.method === "PATCH") {
        const body = JSON.parse(String(init.body)) as { sort_column: string; sort_direction: string }
        sortColumn = body.sort_column
        sortDirection = body.sort_direction

        return Promise.resolve(
          new Response(
            JSON.stringify({
              message: "Dashboard preferences updated.",
              dashboard_preferences: {}
            }),
            { status: 200, headers: { "Content-Type": "application/json" } }
          )
        )
      }

      if (path === "/api/v1/app/dashboard/jobs/bulk" && init?.method === "POST") {
        return Promise.resolve(
          new Response(
            JSON.stringify({
              message: "Retry enqueued for 1 job.",
              action: "retry",
              affected_job_ids: [42],
              skipped_job_ids: []
            }),
            { status: 200, headers: { "Content-Type": "application/json" } }
          )
        )
      }

      if (path === "/api/v1/app/dashboard?view=list&subject=job" || path === "/api/v1/app/dashboard?view=list&state=open&subject=job") {
        return Promise.resolve(
          new Response(
            JSON.stringify(
              dashboardPayload({
                subject: "job",
                view: "list",
                page: 2,
                per_page: 10,
                total: 25,
                total_pages: 3,
                preferences: {
                  sort: { column: sortColumn, direction: sortDirection },
                  visible_columns: ["checkbox", "issue", "state", "repository", "latest", "workflows_count", "started"],
                  kanban_lanes: ["queued", "running", "succeeded"],
                  raw: {}
                },
                items: [dashboardJobItem()]
              })
            ),
            { status: 200, headers: { "Content-Type": "application/json" } }
          )
        )
      }

      return Promise.reject(new Error(`Unexpected fetch: ${path}`))
    })

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/dashboard/jobs?view=list"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(screen.getByRole("main", { name: "Dashboard" })).toBeInTheDocument()
    expect(await screen.findByText("Repair aqueduct")).toBeInTheDocument()
    expect(screen.getAllByText("acme/widgets").length).toBeGreaterThan(0)
    expect(screen.getByRole("link", { name: "kanban" })).toHaveAttribute("href", "/app-shell/dashboard/jobs?view=kanban")
    expect(screen.getByRole("combobox", { name: "State" })).toHaveValue("")
    expect(screen.getByRole("link", { name: "Epics 2" })).toHaveAttribute("href", "/app-shell/dashboard/epics?view=list")
    expect(screen.getByRole("link", { name: "My work" })).toHaveAttribute("href", "/app-shell/dashboard/jobs?view=list&smart_folder_id=7")
    expect(screen.getByText("Showing 11-20 of 25")).toBeInTheDocument()
    expect(screen.getByRole("link", { name: "Previous" })).toHaveAttribute("href", "/app-shell/dashboard/jobs?view=list&page=1")
    expect(screen.getByRole("link", { name: "Next" })).toHaveAttribute("href", "/app-shell/dashboard/jobs?view=list&page=3")
    expect(fetchSpy).toHaveBeenCalledWith(
      "/api/v1/app/dashboard?view=list&subject=job",
      expect.objectContaining({
        credentials: "same-origin",
        headers: { Accept: "application/json" }
      })
    )

    fireEvent.change(screen.getByRole("combobox", { name: "State" }), { target: { value: "open" } })

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/dashboard?view=list&state=open&subject=job",
        expect.objectContaining({
          credentials: "same-origin",
          headers: { Accept: "application/json" }
        })
      )
    })
    expect(await screen.findByText("State: Any open")).toBeInTheDocument()
    expect(screen.getByRole("link", { name: "Clear filters" })).toHaveAttribute("href", "/app-shell/dashboard/jobs?view=list")

    fireEvent.change(screen.getByLabelText("Sort column"), { target: { value: "title" } })

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/dashboard/preferences",
        expect.objectContaining({
          method: "PATCH",
          credentials: "same-origin",
          headers: expect.objectContaining({
            Accept: "application/json",
            "Content-Type": "application/json"
          }),
          body: JSON.stringify({
            subject: "job",
            sort_column: "title",
            sort_direction: "desc"
          })
        })
      )
    })
    expect(await screen.findByText("Dashboard preferences updated.")).toBeInTheDocument()

    fireEvent.click(screen.getByLabelText("Workflows count"))

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/dashboard/preferences",
        expect.objectContaining({
          method: "PATCH",
          credentials: "same-origin",
          headers: expect.objectContaining({
            Accept: "application/json",
            "Content-Type": "application/json"
          }),
          body: JSON.stringify({
            subject: "job",
            visible_columns: ["state", "repository", "latest", "started"]
          })
        })
      )
    })

    fireEvent.click(screen.getByLabelText("Select Repair aqueduct"))
    fireEvent.click(screen.getByRole("button", { name: "Retry" }))

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/dashboard/jobs/bulk",
        expect.objectContaining({
          method: "POST",
          credentials: "same-origin",
          headers: expect.objectContaining({
            Accept: "application/json",
            "Content-Type": "application/json"
          }),
          body: JSON.stringify({
            job_ids: [42],
            bulk_action: "retry"
          })
        })
      )
    })
    expect(await screen.findByText("Retry enqueued for 1 job.")).toBeInTheDocument()
  })

  it("toggles landing queue pause from the React dashboard", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input, init) => {
      const path = String(input)
      if (path === "/api/v1/app/dashboard/landing_pause" && init?.method === "POST") {
        return Promise.resolve(
          new Response(
            JSON.stringify({
              message: "Landing paused.",
              landing_paused: true
            }),
            { status: 200, headers: { "Content-Type": "application/json" } }
          )
        )
      }

      return Promise.resolve(
        new Response(
          JSON.stringify(
            dashboardPayload({
              subject: "job",
              view: "list",
              active_smart_folder_id: 7,
              smart_folders: [
                {
                  id: 7,
                  name: "Landing queue",
                  kind: "builtin",
                  subject_type: "job",
                  active: true,
                  path: "/dashboard/jobs?view=list&smart_folder_id=7"
                }
              ],
              landing_queue: {
                visible: true,
                paused: false,
                toggle_path: "/api/v1/app/dashboard/landing_pause"
              },
              items: [dashboardJobItem()]
            })
          ),
          { status: 200, headers: { "Content-Type": "application/json" } }
        )
      )
    })

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/dashboard/jobs?view=list&smart_folder_id=7"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    fireEvent.click(await screen.findByRole("button", { name: "Pause landing" }))

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/dashboard/landing_pause",
        expect.objectContaining({
          method: "POST",
          credentials: "same-origin",
          headers: expect.objectContaining({
            Accept: "application/json",
            "Content-Type": "application/json"
          }),
          body: JSON.stringify({})
        })
      )
    })
    expect(await screen.findByText("Landing paused.")).toBeInTheDocument()
  })

  it("renders app-shell dashboard kanban lanes from the app dashboard API", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input, init) => {
      const path = String(input)
      if (path === "/api/v1/app/dashboard/preferences" && init?.method === "PATCH") {
        return Promise.resolve(
          new Response(
            JSON.stringify({
              message: "Dashboard preferences updated.",
              dashboard_preferences: {}
            }),
            { status: 200, headers: { "Content-Type": "application/json" } }
          )
        )
      }

      return Promise.resolve(
        new Response(
          JSON.stringify(
            dashboardPayload({
              subject: "job",
              view: "kanban",
              total: 1,
              lanes: [
                { key: "queued", title: "Queued", count: 0, items: [] },
                { key: "running", title: "Running", count: 1, items: [dashboardJobItem()] },
                { key: "succeeded", title: "Succeeded", count: 0, items: [] }
              ],
              kanban_limit: 100
            })
          ),
          { status: 200, headers: { "Content-Type": "application/json" } }
        )
      )
    })

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/dashboard/jobs?view=kanban"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(await screen.findByRole("heading", { name: "Running" })).toBeInTheDocument()
    expect(screen.getByText("Repair aqueduct")).toBeInTheDocument()
    expect(screen.queryByText(/Showing/)).not.toBeInTheDocument()
    expect(fetchSpy).toHaveBeenCalledWith(
      "/api/v1/app/dashboard?view=kanban&subject=job",
      expect.objectContaining({
        credentials: "same-origin",
        headers: { Accept: "application/json" }
      })
    )

    fireEvent.click(screen.getByLabelText("Succeeded"))

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/dashboard/preferences",
        expect.objectContaining({
          method: "PATCH",
          credentials: "same-origin",
          headers: expect.objectContaining({
            Accept: "application/json",
            "Content-Type": "application/json"
          }),
          body: JSON.stringify({
            subject: "job",
            kanban_lanes: ["queued", "running"]
          })
        })
      )
    })
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

  it("renders the admin stuck route from the app admin stuck API", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockResolvedValue(
      new Response(
        JSON.stringify({
          items: [
            {
              kind: "stale_heartbeat",
              severity: "warn",
              detail: "Run #4 silent for 10m",
              age_label: "10m",
              run_id: 4,
              workflow_id: 2,
              workflow_trigger_kind: "initial",
              step_kind: "implement",
              job_id: 1,
              has_transcript: true
            }
          ]
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      )
    )

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/admin/stuck"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(screen.getByRole("main", { name: "Admin stuck items" })).toBeInTheDocument()
    expect(await screen.findByText("Run #4 silent for 10m")).toBeInTheDocument()
    expect(screen.getByText("stale_heartbeat")).toBeInTheDocument()
    expect(screen.getByRole("link", { name: "Job" })).toHaveAttribute("href", "/jobs/1")
    expect(screen.getByRole("link", { name: "Transcript" })).toHaveAttribute("href", "/admin/runs/4/transcript")
    expect(fetchSpy).toHaveBeenCalledWith(
      "/api/v1/app/admin/stuck",
      expect.objectContaining({
        credentials: "same-origin",
        headers: { Accept: "application/json" }
      })
    )
  })

  it("renders the admin processes route from the app admin processes API", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockResolvedValue(
      new Response(
        JSON.stringify({
          running_total: 1,
          processes: [
            {
              id: 8,
              kind: "agent",
              command: "claude --print",
              workdir: "/work",
              hostname: "worker-a",
              pid: 123,
              pgid: 123,
              started_at: "2026-05-30T12:00:00Z",
              last_chunk_at: "2026-05-30T12:01:00Z",
              finished_at: null,
              duration_s: 65,
              exit_status: null,
              outcome: null,
              wall_timeout_s: 1800,
              silent_timeout_s: 300,
              run_id: 4,
              workflow_id: 2,
              stale: false,
              kill_requested_at: null,
              kill_requested_by_user_id: null
            }
          ]
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      )
    )

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/admin/processes?state=running"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(screen.getByRole("main", { name: "Admin processes" })).toBeInTheDocument()
    expect(await screen.findByText("claude --print")).toBeInTheDocument()
    expect(screen.getByText("worker-a")).toBeInTheDocument()
    expect(screen.getByRole("link", { name: "Detail" })).toHaveAttribute("href", "/app-shell/admin/processes/8")
    expect(screen.getByRole("button", { name: "Kill" })).toBeInTheDocument()
    expect(fetchSpy).toHaveBeenCalledWith(
      "/api/v1/app/admin/processes?state=running",
      expect.objectContaining({
        credentials: "same-origin",
        headers: { Accept: "application/json" }
      })
    )
  })

  it("renders the admin users route from the app admin users API", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockResolvedValue(
      new Response(
        JSON.stringify({
          filters: { gh_rate: "low" },
          count: 1,
          users: [
            {
              id: 5,
              email_address: "operator@example.com",
              name: "Operator",
              display_name: "Operator",
              github_handle: "octo",
              admin: true,
              scheduling_paused: false,
              agent_provider: "codex",
              codex_auth_mode: "api_key",
              has_github_token: true,
              has_claude_token: false,
              has_codex_token: true,
              has_codex_api_key: true,
              has_codex_auth_json: false,
              has_api_token: true,
              agent_max_turns: 200,
              github_api_blocked: false,
              github_api_blocked_at: null,
              github_api_blocked_reason: null,
              github_rate_limit: {
                remaining: 5,
                limit: 5000,
                resource: "core",
                reset_at: null,
                observed_at: null,
                percent: 0.001
              },
              created_at: "2026-05-30T12:00:00Z",
              updated_at: "2026-05-30T12:00:00Z"
            }
          ]
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      )
    )

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/admin/users?gh_rate=low"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(screen.getByRole("main", { name: "Admin users" })).toBeInTheDocument()
    expect(await screen.findByText("Operator")).toBeInTheDocument()
    expect(screen.getByText("operator@example.com")).toBeInTheDocument()
    expect(screen.getByRole("link", { name: "Operator" })).toHaveAttribute("href", "/app-shell/admin/users/5")
    expect(fetchSpy).toHaveBeenCalledWith(
      "/api/v1/app/admin/users?gh_rate=low",
      expect.objectContaining({
        credentials: "same-origin",
        headers: { Accept: "application/json" }
      })
    )
  })

  it("renders the admin transcript route from the app admin transcript API", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockResolvedValue(
      new Response(
        JSON.stringify({
          run_id: 4,
          job_id: 1,
          step_kind: "implement",
          workflow_trigger_kind: "initial",
          session_id: "abc-123",
          summary: {
            session_id: "abc-123",
            model: "claude-sonnet-4-6",
            cwd: "/workspace",
            total_turns: 1,
            total_tool_calls: 1,
            total_cost_usd: 0.01,
            exit_reason: "success",
            tool_call_counts: { Bash: 1 },
            mcp_tool_called: false,
            available_tools_at_init: ["Bash"]
          },
          pagination: {
            page: 2,
            per: 1,
            total_events: 3,
            total_pages: 3
          },
          events: [
            {
              kind: "tool_use",
              timestamp: "2026-05-30T12:00:00Z",
              data: { name: "Bash", input: { command: "ls" }, id: "u1" }
            }
          ]
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      )
    )

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/admin/runs/4/transcript?page=2&per=1"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(screen.getByRole("main", { name: "Admin transcript" })).toBeInTheDocument()
    expect(await screen.findByText("Run #4 · transcript")).toBeInTheDocument()
    expect(screen.getByText(/claude-sonnet-4-6/)).toBeInTheDocument()
    expect(screen.getAllByText("Bash").length).toBeGreaterThan(0)
    expect(screen.getByRole("link", { name: "Next" })).toHaveAttribute("href", "/app-shell/admin/runs/4/transcript?page=3&per=1")
    expect(fetchSpy).toHaveBeenCalledWith(
      "/api/v1/app/admin/runs/4/transcript?page=2&per=1",
      expect.objectContaining({
        credentials: "same-origin",
        headers: { Accept: "application/json" }
      })
    )
  })

  it("renders the admin console route from the app admin console API", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockResolvedValue(
      new Response(
        JSON.stringify({
          settings: {
            polling_paused: false,
            runs_paused: true,
            signups_open: true,
            max_job_failures: 3,
            grade_max_iterations: 2
          },
          users: [
            { id: 1, email_address: "operator@example.com", display_name: "Operator" }
          ],
          recent_admin_actions: [
            {
              id: 4,
              action: "pause_runs",
              performed_at: "2026-05-30T12:00:00Z",
              user_email: "operator@example.com",
              params: { source: "test" }
            }
          ]
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      )
    )

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/admin/console"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(screen.getByRole("main", { name: "Admin console" })).toBeInTheDocument()
    expect(screen.getByText("Operator Console")).toBeInTheDocument()
    expect(await screen.findByText("pause_runs")).toBeInTheDocument()
    expect(screen.getByRole("button", { name: "Pause polling" })).toBeInTheDocument()
    expect(screen.getByRole("button", { name: "Resume runs" })).toBeInTheDocument()
    expect(screen.getByRole("button", { name: "Reap now" })).toBeInTheDocument()
    expect(fetchSpy).toHaveBeenCalledWith(
      "/api/v1/app/admin/console",
      expect.objectContaining({
        credentials: "same-origin",
        headers: { Accept: "application/json" }
      })
    )
  })

  it("renders the admin installations route from the app admin installations API", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockResolvedValue(
      new Response(
        JSON.stringify({
          github_app_registered: true,
          github_app_slug: "operator-syrus",
          pat_owner_groups: [
            {
              owner: "globex",
              repository_count: 1,
              install_url: "https://github.com/apps/operator-syrus/installations/new/permissions?target_id=101&repository_ids[]=201"
            }
          ],
          repositories: [
            {
              id: 2,
              slug: "globex/pat-repo",
              owner: "globex",
              name: "pat-repo",
              app_credential_active: false,
              credential_mode: "pat",
              account_login: "globex",
              installation_removed_at: null,
              github_owner_id: 101,
              github_repository_id: 201
            }
          ]
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      )
    )

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/admin/installations"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(screen.getByRole("main", { name: "Admin installations" })).toBeInTheDocument()
    expect(screen.getByText("GitHub App Installations")).toBeInTheDocument()
    expect(await screen.findByText("globex/pat-repo")).toBeInTheDocument()
    expect(screen.getByRole("link", { name: "Install on all PAT-only repos in this account" })).toHaveAttribute(
      "href",
      "https://github.com/apps/operator-syrus/installations/new/permissions?target_id=101&repository_ids[]=201"
    )
    expect(fetchSpy).toHaveBeenCalledWith(
      "/api/v1/app/admin/installations",
      expect.objectContaining({
        credentials: "same-origin",
        headers: { Accept: "application/json" }
      })
    )
  })

  it("renders the invitations route from the app admin invitations API and revokes invitations", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input, init) => {
      const path = String(input)
      if (path === "/api/v1/app/admin/invitations/9" && init?.method === "DELETE") {
        return Promise.resolve(
          new Response(
            JSON.stringify({
              invitations: [],
              message: "Invitation revoked."
            }),
            { status: 200, headers: { "Content-Type": "application/json" } }
          )
        )
      }

      return Promise.resolve(
        new Response(
          JSON.stringify({
            invitations: [
              {
                id: 9,
                email_address: "guest@example.com",
                token: "abc123",
                share_url: "http://example.test/users/new?token=abc123",
                expires_at: "2026-06-06T12:00:00Z",
                created_at: "2026-05-30T12:00:00Z",
                invited_by_email_address: "operator@example.com"
              }
            ]
          }),
          { status: 200, headers: { "Content-Type": "application/json" } }
        )
      )
    })

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/invitations"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(screen.getByRole("main", { name: "Admin invitations" })).toBeInTheDocument()
    expect(await screen.findByText("guest@example.com")).toBeInTheDocument()
    expect(screen.getByText("http://example.test/users/new?token=abc123")).toBeInTheDocument()

    fireEvent.click(screen.getByRole("button", { name: "Revoke" }))

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/admin/invitations/9",
        expect.objectContaining({
          method: "DELETE",
          credentials: "same-origin",
          headers: { Accept: "application/json" }
        })
      )
    })
    expect(await screen.findByText("No pending invitations.")).toBeInTheDocument()
  })

  it("renders the app settings route from the app admin settings API and updates settings", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input, init) => {
      const path = String(input)
      if (path === "/api/v1/app/admin/settings" && init?.method === "PATCH") {
        return Promise.resolve(
          new Response(
            JSON.stringify({
              settings: {
                signups_open: true,
                clearable_secrets: [
                  { key: "telegram_bot_token", label: "Telegram bot token", set: true },
                  { key: "telegram_webhook_secret", label: "Telegram webhook secret", set: false }
                ]
              },
              message: "Settings updated."
            }),
            { status: 200, headers: { "Content-Type": "application/json" } }
          )
        )
      }

      return Promise.resolve(
        new Response(
          JSON.stringify({
            settings: {
              signups_open: false,
              clearable_secrets: [
                { key: "telegram_bot_token", label: "Telegram bot token", set: true },
                { key: "telegram_webhook_secret", label: "Telegram webhook secret", set: false }
              ]
            }
          }),
          { status: 200, headers: { "Content-Type": "application/json" } }
        )
      )
    })

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/settings/edit"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(screen.getByRole("main", { name: "Admin settings" })).toBeInTheDocument()
    expect((await screen.findAllByText("Telegram bot token")).length).toBeGreaterThan(0)
    expect(screen.getByRole("button", { name: "Clear" })).toBeInTheDocument()

    fireEvent.click(screen.getByRole("checkbox", { name: /Open signups/ }))
    fireEvent.change(screen.getByLabelText("Telegram bot token"), { target: { value: "bot-token" } })
    fireEvent.click(screen.getByRole("button", { name: "Save" }))

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/admin/settings",
        expect.objectContaining({
          method: "PATCH",
          credentials: "same-origin",
          headers: expect.objectContaining({
            Accept: "application/json",
            "Content-Type": "application/json"
          }),
          body: JSON.stringify({
            app_setting: {
              signups_open: true,
              telegram_bot_token: "bot-token",
              telegram_webhook_secret: ""
            }
          })
        })
      )
    })
    expect(await screen.findByText("Settings updated.")).toBeInTheDocument()
  })

  it("renders the tags route from the app tags API and creates tags", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input, init) => {
      const path = String(input)
      const palette = [
        { key: "gray", label: "Gray", bg: "#f3f4f6", text: "#374151" },
        { key: "blue", label: "Blue", bg: "#dbeafe", text: "#1d4ed8" },
        { key: "indigo", label: "Indigo", bg: "#e0e7ff", text: "#3730a3" }
      ]

      if (path === "/api/v1/app/tags" && init?.method === "POST") {
        return Promise.resolve(
          new Response(
            JSON.stringify({
              palette,
              tags: [
                { id: 4, name: "epic:attachments", color: "indigo", jobs_count: 0 }
              ],
              message: "Tag created."
            }),
            { status: 201, headers: { "Content-Type": "application/json" } }
          )
        )
      }

      return Promise.resolve(
        new Response(
          JSON.stringify({
            palette,
            tags: [
              { id: 2, name: "triage", color: "blue", jobs_count: 3 }
            ]
          }),
          { status: 200, headers: { "Content-Type": "application/json" } }
        )
      )
    })

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/tags"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(screen.getByRole("main", { name: "Tags" })).toBeInTheDocument()
    expect(await screen.findByText("triage")).toBeInTheDocument()
    expect(screen.getByText("3")).toBeInTheDocument()

    fireEvent.change(screen.getByLabelText("Name"), { target: { value: "epic:attachments" } })
    fireEvent.change(screen.getByLabelText("Color"), { target: { value: "indigo" } })
    fireEvent.click(screen.getByRole("button", { name: "Create" }))

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/tags",
        expect.objectContaining({
          method: "POST",
          credentials: "same-origin",
          headers: expect.objectContaining({
            Accept: "application/json",
            "Content-Type": "application/json"
          }),
          body: JSON.stringify({
            tag: {
              name: "epic:attachments",
              color: "indigo"
            }
          })
        })
      )
    })
    expect(await screen.findByText("Tag created.")).toBeInTheDocument()
    expect(screen.getByText("epic:attachments")).toBeInTheDocument()
  })

  it("renders the smart folders route from the app API and updates folders", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input, init) => {
      const path = String(input)
      if (path === "/api/v1/app/smart_folders/7" && init?.method === "PATCH") {
        return Promise.resolve(
          new Response(
            JSON.stringify({
              subject_type: "epic",
              subject_label: "Epic",
              dashboard_path: "/dashboard/epics",
              smart_folders: [
                {
                  id: 7,
                  name: "Ready Epics",
                  position: 3,
                  filter: { and: [{ field: "state", op: "is", value: "ready" }] }
                }
              ],
              message: "Smart folder updated."
            }),
            { status: 200, headers: { "Content-Type": "application/json" } }
          )
        )
      }

      return Promise.resolve(
        new Response(
          JSON.stringify({
            subject_type: "epic",
            subject_label: "Epic",
            dashboard_path: "/dashboard/epics",
            smart_folders: [
              {
                id: 7,
                name: "Ready Epics",
                position: 2,
                filter: { and: [{ field: "state", op: "is", value: "ready" }] }
              }
            ]
          }),
          { status: 200, headers: { "Content-Type": "application/json" } }
        )
      )
    })

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/smart_folders?subject_type=epic"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(screen.getByRole("main", { name: "Smart folders" })).toBeInTheDocument()
    expect(await screen.findByDisplayValue("Ready Epics")).toBeInTheDocument()
    expect(screen.getByRole("link", { name: "Back to dashboard" })).toHaveAttribute("href", "/dashboard/epics")

    fireEvent.change(screen.getByLabelText("Position for Ready Epics"), { target: { value: "3" } })
    fireEvent.click(screen.getByRole("button", { name: "Save" }))

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/smart_folders/7",
        expect.objectContaining({
          method: "PATCH",
          credentials: "same-origin",
          headers: expect.objectContaining({
            Accept: "application/json",
            "Content-Type": "application/json"
          }),
          body: JSON.stringify({
            smart_folder: {
              name: "Ready Epics",
              position: 3
            }
          })
        })
      )
    })
    expect(await screen.findByText("Smart folder updated.")).toBeInTheDocument()
  })

  it("renders the cron templates route from the app API and links to detail", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockResolvedValue(
      new Response(
        JSON.stringify({
          pr_pileup_policies: ["skip", "pile", "replace"],
          templates: [
            {
              id: 5,
              name: "Weekly dependency bump",
              description: "Keep dependencies moving.",
              cron_expression: "0 9 * * 1",
              pr_pileup_policy: "skip",
              enabled: true,
              applied_tasks_count: 2,
              created_at: "2026-05-30T12:00:00Z",
              updated_at: "2026-05-30T12:00:00Z"
            }
          ]
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      )
    )

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/cron_templates"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(screen.getByRole("main", { name: "Cron templates" })).toBeInTheDocument()
    expect(await screen.findByText("Weekly dependency bump")).toBeInTheDocument()
    expect(screen.getByRole("link", { name: "Weekly dependency bump" })).toHaveAttribute("href", "/app-shell/cron_templates/5")
    expect(screen.getByText("2 repos")).toBeInTheDocument()
    expect(fetchSpy).toHaveBeenCalledWith(
      "/api/v1/app/cron_templates",
      expect.objectContaining({
        credentials: "same-origin",
        headers: { Accept: "application/json" }
      })
    )
  })

  it("renders the scheduled tasks route from the app API", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockResolvedValue(
      new Response(
        JSON.stringify({
          active_tasks: [
            {
              id: 12,
              name: "Weekly tests",
              kind: "cron",
              state: "scheduled",
              repository: { id: 3, slug: "acme/widgets", repository_path: "/repositories/3" },
              schedule_label: "17 9 * * 1",
              last_fired_at: null,
              archived_at: null,
              consecutive_failure_count: 0,
              scheduled_task_path: "/scheduled_tasks/12"
            }
          ],
          fired_one_shots: [],
          archived_tasks: [],
          options: scheduledTaskOptions()
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      )
    )

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/scheduled_tasks"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(screen.getByRole("main", { name: "Scheduled tasks" })).toBeInTheDocument()
    expect(await screen.findByText("Weekly tests")).toBeInTheDocument()
    expect(screen.getByRole("link", { name: "Weekly tests" })).toHaveAttribute("href", "/app-shell/scheduled_tasks/12")
    expect(screen.getByText("acme/widgets")).toBeInTheDocument()
    expect(fetchSpy).toHaveBeenCalledWith(
      "/api/v1/app/scheduled_tasks",
      expect.objectContaining({
        credentials: "same-origin",
        headers: { Accept: "application/json" }
      })
    )
  })

  it("renders scheduled task detail and pauses the task", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input, init) => {
      const path = String(input)
      if (path === "/api/v1/app/scheduled_tasks/12/pause" && init?.method === "POST") {
        return Promise.resolve(new Response(JSON.stringify(scheduledTaskDetailPayload({ state: "paused", message: "Paused." })), { status: 200, headers: { "Content-Type": "application/json" } }))
      }

      return Promise.resolve(new Response(JSON.stringify(scheduledTaskDetailPayload()), { status: 200, headers: { "Content-Type": "application/json" } }))
    })

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/scheduled_tasks/12"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(await screen.findByRole("main", { name: "Scheduled task detail" })).toBeInTheDocument()
    expect(await screen.findByText("Keep tests moving.")).toBeInTheDocument()
    fireEvent.click(screen.getByRole("button", { name: "Pause" }))

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/scheduled_tasks/12/pause",
        expect.objectContaining({
          method: "POST",
          credentials: "same-origin"
        })
      )
    })
    expect(await screen.findByText("Paused.")).toBeInTheDocument()
  })

  it("renders the repository scheduled task form and creates a task", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input, init) => {
      const path = String(input)
      if (path === "/api/v1/app/repositories/3/scheduled_tasks?from_template=9" && init?.method === "POST") {
        return Promise.resolve(new Response(JSON.stringify(scheduledTaskDetailPayload({ message: "Scheduled task created." })), { status: 201, headers: { "Content-Type": "application/json" } }))
      }

      return Promise.resolve(
        new Response(
          JSON.stringify({
            task: {
              id: null,
              name: "Weekly tests",
              kind: "cron",
              cron_expression: "0 9 * * 1",
              fire_at: null,
              pr_pileup_policy: "skip",
              auto_approve_mode: "never",
              prompt: "Keep tests moving.",
              cron_template_id: 9
            },
            repository: { id: 3, slug: "acme/widgets", repository_path: "/repositories/3" },
            from_template: { id: 9, name: "Template", cron_template_path: "/cron_templates/9" },
            options: scheduledTaskOptions()
          }),
          { status: 200, headers: { "Content-Type": "application/json" } }
        )
      )
    })

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/repositories/3/scheduled_tasks/new?from_template=9"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(await screen.findByRole("main", { name: "New scheduled task" })).toBeInTheDocument()
    expect(await screen.findByDisplayValue("Weekly tests")).toBeInTheDocument()
    fireEvent.click(screen.getByRole("button", { name: "Create task" }))

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/repositories/3/scheduled_tasks?from_template=9",
        expect.objectContaining({
          method: "POST",
          credentials: "same-origin",
          body: JSON.stringify({
            scheduled_task: {
              name: "Weekly tests",
              prompt: "Keep tests moving.",
              kind: "cron",
              cron_expression: "0 9 * * 1",
              fire_at: "",
              pr_pileup_policy: "skip",
              auto_approve_mode: "never"
            }
          })
        })
      )
    })
  })

  it("renders the repository scheduled tasks route and disables a task", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input, init) => {
      const path = String(input)
      if (path === "/api/v1/app/repositories/3/scheduled_tasks/12" && init?.method === "PATCH") {
        return Promise.resolve(new Response(JSON.stringify(repositoryScheduledTasksPayload({ state: "paused", active: false, message: "Scheduled task disabled." })), { status: 200, headers: { "Content-Type": "application/json" } }))
      }

      return Promise.resolve(new Response(JSON.stringify(repositoryScheduledTasksPayload()), { status: 200, headers: { "Content-Type": "application/json" } }))
    })

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/repositories/3/scheduled_tasks"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(await screen.findByRole("main", { name: "Repository scheduled tasks" })).toBeInTheDocument()
    expect(await screen.findByText("Daily review")).toBeInTheDocument()
    expect(screen.getByRole("link", { name: "New scheduled task" })).toHaveAttribute("href", "/app-shell/repositories/3/scheduled_tasks/new")
    fireEvent.click(screen.getByRole("button", { name: "Disable" }))

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/repositories/3/scheduled_tasks/12",
        expect.objectContaining({
          method: "PATCH",
          credentials: "same-origin",
          body: JSON.stringify({ enabled: false })
        })
      )
    })
    expect(await screen.findByText("Scheduled task disabled.")).toBeInTheDocument()
  })

  it("renders the credentials route and updates account settings", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input, init) => {
      const path = String(input)
      if (path === "/api/v1/app/credentials" && init?.method === "PATCH") {
        return Promise.resolve(new Response(JSON.stringify(credentialsPayload({ name: "Ada Lovelace", message: "Credentials updated." })), { status: 200, headers: { "Content-Type": "application/json" } }))
      }

      return Promise.resolve(new Response(JSON.stringify(credentialsPayload()), { status: 200, headers: { "Content-Type": "application/json" } }))
    })

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/credentials/edit"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(await screen.findByRole("main", { name: "My credentials" })).toBeInTheDocument()
    fireEvent.change(await screen.findByLabelText("Display name"), { target: { value: "Ada Lovelace" } })
    fireEvent.click(screen.getByRole("button", { name: "Save" }))

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/credentials",
        expect.objectContaining({
          method: "PATCH",
          credentials: "same-origin"
        })
      )
    })
    const patchCall = fetchSpy.mock.calls.find((call) => call[0] === "/api/v1/app/credentials" && call[1]?.method === "PATCH")
    const patchBody = JSON.parse(String(patchCall?.[1]?.body))
    expect(patchBody.user).toEqual(expect.objectContaining({
      name: "Ada Lovelace",
      claude_oauth_token: "",
      codex_api_key: "",
      codex_auth_json: "",
      github_token: ""
    }))
    expect(await screen.findByText("Credentials updated.")).toBeInTheDocument()
  })

  it("renders /settings as the credentials route without admin links", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockResolvedValue(
      new Response(JSON.stringify(credentialsPayload()), { status: 200, headers: { "Content-Type": "application/json" } })
    )

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/settings"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(await screen.findByRole("main", { name: "My credentials" })).toBeInTheDocument()
    expect(screen.getByRole("link", { name: "My credentials" })).toHaveAttribute("href", "/app-shell/credentials/edit")
    expect(screen.getByRole("link", { name: "Templates" })).toHaveAttribute("href", "/app-shell/cron_templates")
    expect(screen.getByRole("link", { name: "Tags" })).toHaveAttribute("href", "/app-shell/tags")
    expect(screen.queryByRole("link", { name: "Invitations" })).not.toBeInTheDocument()
    expect(screen.queryByRole("link", { name: "App settings" })).not.toBeInTheDocument()
    expect(fetchSpy).toHaveBeenCalledWith("/api/v1/app/credentials", expect.objectContaining({ credentials: "same-origin" }))
  })

  it("rotates an admin API token from the credentials route", async () => {
    vi.spyOn(window, "confirm").mockReturnValue(true)
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input, init) => {
      const path = String(input)
      if (path === "/api/v1/app/credentials/rotate_api_token" && init?.method === "POST") {
        return Promise.resolve(new Response(JSON.stringify(credentialsPayload({ apiToken: true, newApiToken: "syrus_newtoken", message: "API token rotated." })), { status: 200, headers: { "Content-Type": "application/json" } }))
      }

      return Promise.resolve(new Response(JSON.stringify(credentialsPayload({ apiToken: true })), { status: 200, headers: { "Content-Type": "application/json" } }))
    })

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/credentials/edit"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(await screen.findByRole("button", { name: "Rotate token" })).toBeInTheDocument()
    fireEvent.click(screen.getByRole("button", { name: "Rotate token" }))

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/credentials/rotate_api_token",
        expect.objectContaining({
          method: "POST",
          credentials: "same-origin"
        })
      )
    })
    expect(await screen.findByText("syrus_newtoken")).toBeInTheDocument()
  })

  it("uploads a personal document from the credentials route", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input, init) => {
      const path = String(input)
      if (path === "/api/v1/app/credentials/documents" && init?.method === "POST") {
        return Promise.resolve(new Response(JSON.stringify(credentialsPayload({ documents: [{ id: 8, kind: "google_doc", google_doc_url: "https://docs.google.com/document/d/user/edit", filename: null, content_type: null, byte_size: null, created_at: "2026-05-30T12:00:00Z" }], message: "Document added." })), { status: 201, headers: { "Content-Type": "application/json" } }))
      }

      return Promise.resolve(new Response(JSON.stringify(credentialsPayload()), { status: 200, headers: { "Content-Type": "application/json" } }))
    })

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/credentials/edit"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(await screen.findByRole("main", { name: "My credentials" })).toBeInTheDocument()
    fireEvent.change(await screen.findByLabelText("Google Doc URL"), { target: { value: "https://docs.google.com/document/d/user/edit" } })
    fireEvent.click(screen.getByRole("button", { name: "Add document" }))

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/credentials/documents",
        expect.objectContaining({
          method: "POST",
          credentials: "same-origin",
          body: expect.any(FormData)
        })
      )
    })
    expect(await screen.findByText("Document added.")).toBeInTheDocument()
    expect(screen.getByText("https://docs.google.com/document/d/user/edit")).toBeInTheDocument()
  })

  it("renders repository documents and adds a Google Doc", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input, init) => {
      const path = String(input)
      if (path === "/api/v1/app/repositories/3/documents" && init?.method === "POST") {
        return Promise.resolve(new Response(JSON.stringify(repositoryDocumentsPayload({
          documents: [
            {
              id: 9,
              kind: "google_doc",
              title: "Design brief",
              google_doc_url: "https://docs.google.com/document/d/design/edit",
              filename: null,
              content_type: null,
              byte_size: null,
              uploaded_by: "Operator",
              created_at: "2026-05-30T12:00:00Z"
            }
          ],
          message: "Document added."
        })), { status: 201, headers: { "Content-Type": "application/json" } }))
      }

      return Promise.resolve(new Response(JSON.stringify(repositoryDocumentsPayload()), { status: 200, headers: { "Content-Type": "application/json" } }))
    })

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/repositories/3/documents"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(await screen.findByRole("main", { name: "Repository documents" })).toBeInTheDocument()
    expect(await screen.findByText("No supporting documents yet. Upload a file or link a Google Doc to give the agent extra context.")).toBeInTheDocument()
    fireEvent.change(screen.getByLabelText("URL"), { target: { value: "https://docs.google.com/document/d/design/edit" } })
    fireEvent.change(screen.getByLabelText("Document title"), { target: { value: "Design brief" } })
    fireEvent.click(screen.getByRole("button", { name: "Add Google Doc" }))

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/repositories/3/documents",
        expect.objectContaining({
          method: "POST",
          credentials: "same-origin",
          body: expect.any(FormData)
        })
      )
    })
    expect(await screen.findByText("Document added.")).toBeInTheDocument()
    expect(screen.getByText("Design brief")).toBeInTheDocument()
  })

  it("renders the direct job form, applies a template, and creates another job", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input, init) => {
      const path = String(input)
      if (path === "/api/v1/app/jobs" && init?.method === "POST") {
        return Promise.resolve(
          new Response(
            JSON.stringify({
              message: "Direct job created.",
              create_more: true,
              redirect_to: "/jobs/new?repository_id=3&create_more=1",
              job: {
                id: 44,
                title: "Configure Syrus build dependencies",
                state: "queued",
                repository: {
                  id: 3,
                  slug: "acme/widgets",
                  repository_path: "/repositories/3",
                  default_agent_provider: "codex",
                  default_agent_provider_label: "Codex"
                },
                job_path: "/jobs/44"
              }
            }),
            { status: 201, headers: { "Content-Type": "application/json" } }
          )
        )
      }

      return Promise.resolve(new Response(JSON.stringify(directJobFormPayload()), { status: 200, headers: { "Content-Type": "application/json" } }))
    })

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/jobs/new?repository_id=3&create_more=1"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(await screen.findByRole("main", { name: "New direct job" })).toBeInTheDocument()
    expect(await screen.findByDisplayValue("acme/widgets")).toBeInTheDocument()
    expect(screen.getByLabelText("Create More")).toBeChecked()
    fireEvent.click(screen.getByRole("button", { name: /Configure Syrus build dependencies/ }))
    expect(screen.getByDisplayValue("Configure Syrus build dependencies")).toBeInTheDocument()
    expect(screen.getByDisplayValue("Write a .syrus.yml setup file.")).toBeInTheDocument()
    fireEvent.change(screen.getByLabelText("Google Doc URL"), { target: { value: "https://docs.google.com/document/d/context/edit" } })
    fireEvent.click(screen.getByRole("button", { name: "Create job" }))

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/jobs",
        expect.objectContaining({
          method: "POST",
          credentials: "same-origin",
          body: expect.any(FormData)
        })
      )
    })
    const postCall = fetchSpy.mock.calls.find((call) => call[0] === "/api/v1/app/jobs" && call[1]?.method === "POST")
    const body = postCall?.[1]?.body as FormData
    expect(body.get("repository_id")).toBe("3")
    expect(body.get("agent_provider")).toBe("")
    expect(body.get("title")).toBe("Configure Syrus build dependencies")
    expect(body.get("prompt")).toBe("Write a .syrus.yml setup file.")
    expect(body.get("priority")).toBe("medium")
    expect(body.get("create_more")).toBe("1")
    expect(body.get("job_attachment[google_doc_url]")).toBe("https://docs.google.com/document/d/context/edit")
    expect(await screen.findByText("Direct job created.")).toBeInTheDocument()
  })

  it("renders repositories and polls one from the app API", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input, init) => {
      const path = String(input)
      if (path === "/api/v1/app/repositories/3/poll" && init?.method === "POST") {
        return Promise.resolve(new Response(JSON.stringify(repositoriesPayload({ message: "Polling acme/widgets now." })), { status: 200, headers: { "Content-Type": "application/json" } }))
      }

      return Promise.resolve(new Response(JSON.stringify(repositoriesPayload()), { status: 200, headers: { "Content-Type": "application/json" } }))
    })

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/repositories"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(await screen.findByRole("main", { name: "Repositories" })).toBeInTheDocument()
    expect(await screen.findByText("acme/widgets")).toBeInTheDocument()
    expect(screen.getByText("old/repo")).toBeInTheDocument()
    expect(screen.getByRole("link", { name: "Add" })).toHaveAttribute("href", "/repositories/new")
    expect(screen.getByRole("link", { name: "acme/widgets" })).toHaveAttribute("href", "/repositories/3")
    fireEvent.click(screen.getByRole("button", { name: "Poll now" }))

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/repositories/3/poll",
        expect.objectContaining({
          method: "POST",
          credentials: "same-origin"
        })
      )
    })
    expect(await screen.findByText("Polling acme/widgets now.")).toBeInTheDocument()
  })

  it("renders the repository form with GitHub selectors and submits it to the app API", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input, init) => {
      const path = String(input)
      if (path === "/api/v1/app/repositories" && init?.method === "POST") {
        return Promise.resolve(new Response(
          JSON.stringify({ error: { code: "validation_failed", message: "Owner has already been taken" } }),
          { status: 422, headers: { "Content-Type": "application/json" } }
        ))
      }
      if (path === "/api/v1/app/repositories/owners") {
        return Promise.resolve(new Response(JSON.stringify({ user: "acme", orgs: [] }), { status: 200, headers: { "Content-Type": "application/json" } }))
      }
      if (path === "/api/v1/app/repositories/repos?owner=acme&owner_type=user") {
        return Promise.resolve(new Response(JSON.stringify({
          repos: [
            { name: "widgets", github_repository_id: 456, github_owner_id: 123 }
          ]
        }), { status: 200, headers: { "Content-Type": "application/json" } }))
      }
      if (path === "/api/v1/app/repositories/branches?owner=acme&name=widgets") {
        return Promise.resolve(new Response(JSON.stringify({ branches: ["trunk", "main"], default_branch: "trunk" }), { status: 200, headers: { "Content-Type": "application/json" } }))
      }

      return Promise.resolve(new Response(JSON.stringify(repositoryFormPayload()), { status: 200, headers: { "Content-Type": "application/json" } }))
    })

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/repositories/new"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(await screen.findByRole("main", { name: "Add Repository" })).toBeInTheDocument()
    expect(await screen.findByRole("option", { name: "acme" })).toBeInTheDocument()
    fireEvent.change(screen.getByLabelText("Owner"), { target: { value: "acme" } })
    expect(await screen.findByRole("option", { name: "widgets" })).toBeInTheDocument()
    fireEvent.change(screen.getByLabelText("Name"), { target: { value: "widgets" } })
    expect(await screen.findByRole("option", { name: "trunk" })).toBeInTheDocument()
    fireEvent.change(screen.getByLabelText("Default branch"), { target: { value: "trunk" } })
    fireEvent.change(screen.getByLabelText("Default agent"), { target: { value: "codex" } })
    fireEvent.change(screen.getByLabelText("Auto-approval fallback"), { target: { value: "if_graders_pass" } })
    fireEvent.click(screen.getByLabelText("Run prepare step on this repository's Workflows"))
    fireEvent.click(screen.getByLabelText("Auto-merge approved Syrus PRs"))
    fireEvent.click(screen.getByRole("button", { name: "Create Repository" }))

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/repositories",
        expect.objectContaining({
          method: "POST",
          credentials: "same-origin",
          body: JSON.stringify({
            repository: {
              owner: "acme",
              name: "widgets",
              default_branch: "trunk",
              trigger_label: "syrus",
              polling_enabled: true,
              prepare_enabled: false,
              pr_cost_footer_enabled: true,
              auto_merge_enabled: true,
              agent_provider: "codex",
              auto_approve_mode: "if_graders_pass",
              github_owner_id: "123",
              github_repository_id: "456"
            }
          })
        })
      )
    })
    expect(await screen.findByText("Owner has already been taken")).toBeInTheDocument()
  })

  it("renders the edit repository form and patches repository settings", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input, init) => {
      const path = String(input)
      if (path === "/api/v1/app/repositories/3" && init?.method === "PATCH") {
        return Promise.resolve(new Response(
          JSON.stringify({ error: { code: "validation_failed", message: "Trigger label can't be blank" } }),
          { status: 422, headers: { "Content-Type": "application/json" } }
        ))
      }
      if (path === "/api/v1/app/repositories/owners") {
        return Promise.resolve(new Response(JSON.stringify({ error: "no_token" }), { status: 200, headers: { "Content-Type": "application/json" } }))
      }

      return Promise.resolve(new Response(JSON.stringify(repositoryFormPayload({
        repository: {
          id: 3,
          owner: "acme",
          name: "widgets",
          slug: "acme/widgets",
          default_branch: "main",
          trigger_label: "syrus",
          polling_enabled: true,
          prepare_enabled: true,
          pr_cost_footer_enabled: true,
          auto_merge_enabled: false,
          agent_provider: "",
          auto_approve_mode: "never",
          github_owner_id: null,
          github_repository_id: null,
          repository_path: "/repositories/3"
        }
      })), { status: 200, headers: { "Content-Type": "application/json" } }))
    })

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/repositories/3/edit"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(await screen.findByRole("main", { name: "Edit Repository" })).toBeInTheDocument()
    expect(await screen.findByDisplayValue("acme")).toBeInTheDocument()
    fireEvent.change(screen.getByLabelText("Trigger label"), { target: { value: "delegate" } })
    fireEvent.click(screen.getByRole("button", { name: "Save Repository" }))

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/repositories/3",
        expect.objectContaining({
          method: "PATCH",
          credentials: "same-origin",
          body: expect.stringContaining('"trigger_label":"delegate"')
        })
      )
    })
    expect(await screen.findByText("Trigger label can't be blank")).toBeInTheDocument()
  })

  it("renders a repository detail overview from the app API", async () => {
    vi.spyOn(window, "fetch").mockResolvedValue(
      new Response(JSON.stringify(repositoryDetailPayload()), { status: 200, headers: { "Content-Type": "application/json" } })
    )

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/repositories/3"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(await screen.findByRole("main", { name: "Repository" })).toBeInTheDocument()
    expect(await screen.findByRole("link", { name: "acme/widgets" })).toHaveAttribute("href", "https://github.com/acme/widgets")
    expect(screen.getByText("polling enabled")).toBeInTheDocument()
    expect(screen.getByText("Repository note pinned.")).toBeInTheDocument()
    expect(screen.getByText("Fix forum")).toBeInTheDocument()
    expect(screen.getByText("Retry 1 failed with Codex")).toBeInTheDocument()
    expect(screen.getByText("Install Syrus App on this repository")).toHaveAttribute("href", "https://github.com/apps/operator-syrus/installations/new/permissions?target_id=100&repository_ids[]=200")
    expect(screen.getByText("Running").previousElementSibling).toHaveTextContent("1")
    expect(screen.getByText("Queued").previousElementSibling).toHaveTextContent("1")
    expect(screen.getByText("Failed (7d)").previousElementSibling).toHaveTextContent("1")
  })

  it("runs repository note commands through the app API", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input, init) => {
      const path = String(input)
      if (path === "/api/v1/app/repositories/3/notes/11" && init?.method === "DELETE") {
        return Promise.resolve(new Response(JSON.stringify({
          ...repositoryDetailPayload(),
          message: "Repository note removed.",
          notes: []
        }), { status: 200, headers: { "Content-Type": "application/json" } }))
      }

      if (path === "/api/v1/app/repositories/3/notes" && init?.method === "POST") {
        return Promise.resolve(new Response(JSON.stringify({
          ...repositoryDetailPayload(),
          message: "Repository note pinned.",
          notes: [
            {
              id: 12,
              body: "Use staging for smoke tests.",
              author: "operator",
              created_at: "2026-05-30T12:00:00Z",
              delete_path: "/repositories/3/notes/12",
              app_delete_path: "/api/v1/app/repositories/3/notes/12"
            }
          ]
        }), { status: 200, headers: { "Content-Type": "application/json" } }))
      }

      return Promise.resolve(new Response(JSON.stringify(repositoryDetailPayload()), { status: 200, headers: { "Content-Type": "application/json" } }))
    })

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/repositories/3"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    fireEvent.click(await screen.findByRole("button", { name: "Delete" }))
    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/repositories/3/notes/11",
        expect.objectContaining({ method: "DELETE", credentials: "same-origin" })
      )
    })
    expect(await screen.findByText("Repository note removed.")).toBeInTheDocument()

    fireEvent.change(screen.getByPlaceholderText("Pin repository context..."), { target: { value: "Use staging for smoke tests." } })
    fireEvent.click(screen.getByRole("button", { name: "Add note" }))
    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/repositories/3/notes",
        expect.objectContaining({
          method: "POST",
          credentials: "same-origin",
          body: JSON.stringify({ repository_note: { body: "Use staging for smoke tests." } })
        })
      )
    })
    expect(await screen.findByText("Use staging for smoke tests.")).toBeInTheDocument()
  })

  it("runs repository detail commands through the app API", async () => {
    vi.spyOn(window, "confirm").mockReturnValue(true)
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input, init) => {
      const path = String(input)
      if (path === "/api/v1/app/repositories/3/poll" && init?.method === "POST") {
        return Promise.resolve(new Response(JSON.stringify({
          ...repositoryDetailPayload(),
          message: "Polling acme/widgets now."
        }), { status: 200, headers: { "Content-Type": "application/json" } }))
      }

      if (path === "/api/v1/app/repositories/3/retry_failed_jobs" && init?.method === "POST") {
        return Promise.resolve(new Response(JSON.stringify({
          ...repositoryDetailPayload(),
          message: "Retry enqueued for 1 failed job with Codex.",
          retry_failed_jobs: {
            count: 0,
            agent_provider: "codex",
            agent_provider_label: "Codex"
          }
        }), { status: 200, headers: { "Content-Type": "application/json" } }))
      }

      if (path === "/api/v1/app/repositories/3/archive" && init?.method === "POST") {
        return Promise.resolve(new Response(JSON.stringify(repositoriesPayload({ message: "acme/widgets archived." })), { status: 200, headers: { "Content-Type": "application/json" } }))
      }

      if (path === "/api/v1/app/repositories") {
        return Promise.resolve(new Response(JSON.stringify(repositoriesPayload({ message: "acme/widgets archived." })), { status: 200, headers: { "Content-Type": "application/json" } }))
      }

      return Promise.resolve(new Response(JSON.stringify(repositoryDetailPayload()), { status: 200, headers: { "Content-Type": "application/json" } }))
    })

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/repositories/3"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    fireEvent.click(await screen.findByRole("button", { name: "Poll now" }))
    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/repositories/3/poll",
        expect.objectContaining({
          method: "POST",
          credentials: "same-origin",
          body: JSON.stringify({ return_to: "detail", page: 1 })
        })
      )
    })
    expect(await screen.findByText("Polling acme/widgets now.")).toBeInTheDocument()

    fireEvent.click(screen.getByRole("button", { name: "Retry 1 failed with Codex" }))
    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/repositories/3/retry_failed_jobs",
        expect.objectContaining({
          method: "POST",
          credentials: "same-origin",
          body: JSON.stringify({ page: 1 })
        })
      )
    })
    expect(await screen.findByText("Retry enqueued for 1 failed job with Codex.")).toBeInTheDocument()

    fireEvent.click(screen.getByRole("button", { name: "Archive" }))
    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/repositories/3/archive",
        expect.objectContaining({ method: "POST", credentials: "same-origin" })
      )
    })
    expect(await screen.findByRole("main", { name: "Repositories" })).toBeInTheDocument()
  })

  it("renders repository GitHub issues and delegates one through the app API", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input, init) => {
      const path = String(input)
      if (path === "/api/v1/app/repositories/3/issues/delegate" && init?.method === "POST") {
        return Promise.resolve(new Response(JSON.stringify(repositoryIssuesPayload({
          message: "Issue #7 delegated to Syrus.",
          delegated: true
        })), { status: 200, headers: { "Content-Type": "application/json" } }))
      }

      return Promise.resolve(new Response(JSON.stringify(repositoryIssuesPayload()), { status: 200, headers: { "Content-Type": "application/json" } }))
    })

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/repositories/3?tab=github_issues&state=open"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(await screen.findByRole("main", { name: "Repository" })).toBeInTheDocument()
    expect(await screen.findByText("Fix the forum")).toBeInTheDocument()
    expect(screen.getByText("Trigger label:")).toBeInTheDocument()
    expect(screen.getByRole("link", { name: "View on GitHub" })).toHaveAttribute("href", "https://github.com/acme/widgets/issues")
    fireEvent.click(screen.getByRole("button", { name: "Delegate" }))

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/repositories/3/issues/delegate",
        expect.objectContaining({
          method: "POST",
          credentials: "same-origin",
          body: JSON.stringify({ issue_number: 7, state: "open" })
        })
      )
    })
    expect(await screen.findByText("Issue #7 delegated to Syrus.")).toBeInTheDocument()
    expect(screen.getByText("Delegated")).toBeInTheDocument()
  })

  it("renders the new epic form and submits it to the app API", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input, init) => {
      const path = String(input)
      if (path === "/api/v1/app/epics" && init?.method === "POST") {
        return Promise.resolve(
          new Response(
            JSON.stringify({
              error: {
                code: "validation_failed",
                message: "Title can't be blank"
              }
            }),
            { status: 422, headers: { "Content-Type": "application/json" } }
          )
        )
      }

      return Promise.resolve(new Response(JSON.stringify(epicFormPayload()), { status: 200, headers: { "Content-Type": "application/json" } }))
    })

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/epics/new"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(await screen.findByRole("main", { name: "New Epic" })).toBeInTheDocument()
    fireEvent.change(await screen.findByLabelText("Title"), { target: { value: "Raise the forum" } })
    fireEvent.change(screen.getByLabelText("Description"), { target: { value: "Install tasteful columns." } })
    fireEvent.change(screen.getByLabelText("Repository"), { target: { value: "3" } })
    fireEvent.change(screen.getByLabelText("GitHub issue URL"), { target: { value: "https://github.com/acme/widgets/issues/12" } })
    fireEvent.click(screen.getByRole("button", { name: "Create Epic" }))

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/epics",
        expect.objectContaining({
          method: "POST",
          credentials: "same-origin",
          body: JSON.stringify({
            epic: {
              title: "Raise the forum",
              description: "Install tasteful columns.",
              repository_id: "3",
              github_issue_url: "https://github.com/acme/widgets/issues/12"
            }
          })
        })
      )
    })
    expect(await screen.findByText("Title can't be blank")).toBeInTheDocument()
  })

  it("renders an Epic detail page and updates state through the app API", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input, init) => {
      const path = String(input)
      if (path === "/api/v1/app/epics/7/state" && init?.method === "PATCH") {
        return Promise.resolve(new Response(JSON.stringify(epicDetailPayload({
          message: "Epic updated.",
          state: "in_progress",
          stateTransitions: [
            { label: "Move back to ready", target_state: "ready", confirm: null },
            { label: "Archive", target_state: "archived", confirm: "Archive this Epic?" }
          ]
        })), { status: 200, headers: { "Content-Type": "application/json" } }))
      }

      return Promise.resolve(new Response(JSON.stringify(epicDetailPayload()), { status: 200, headers: { "Content-Type": "application/json" } }))
    })

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/epics/7"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(await screen.findByRole("main", { name: "Epic" })).toBeInTheDocument()
    expect(await screen.findByText("EPIC-7")).toBeInTheDocument()
    expect(screen.getByText("Raise the forum")).toBeInTheDocument()
    expect(screen.getByText("columns")).toBeInTheDocument()
    expect(screen.getByText("(1 epic dep, 0 job blockers)")).toBeInTheDocument()
    expect(screen.getByText("Survey forum")).toBeInTheDocument()
    expect(screen.getByText("1/1 done")).toBeInTheDocument()

    fireEvent.click(screen.getByRole("button", { name: "Start" }))

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/epics/7/state",
        expect.objectContaining({
          method: "PATCH",
          credentials: "same-origin",
          body: JSON.stringify({ target_state: "in_progress" })
        })
      )
    })
    expect(await screen.findByText("Epic updated.")).toBeInTheDocument()
    expect(screen.getByText("In Progress")).toBeInTheDocument()
  })

  it("renders a Job detail page and runs commands through the app API", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input, init) => {
      const path = String(input)
      if (path === "/api/v1/app/jobs/42/poll_feedback" && init?.method === "POST") {
        return Promise.resolve(new Response(JSON.stringify({ message: "Checking PR feedback now..." }), { status: 200, headers: { "Content-Type": "application/json" } }))
      }
      if (path === "/api/v1/app/jobs/42/timeline") {
        return Promise.resolve(new Response(JSON.stringify(jobTimelinePayload()), { status: 200, headers: { "Content-Type": "application/json" } }))
      }

      return Promise.resolve(new Response(JSON.stringify(jobDetailPayload()), { status: 200, headers: { "Content-Type": "application/json" } }))
    })

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/jobs/42"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(await screen.findByRole("main", { name: "Job" })).toBeInTheDocument()
    expect(await screen.findByText("Repair aqueduct")).toBeInTheDocument()
    expect(screen.getByText("Water should climb the hill.")).toBeInTheDocument()
    expect(screen.getByText("Moved the uphill water simulation.")).toBeInTheDocument()
    expect(await screen.findByText("Workflow created")).toBeInTheDocument()

    fireEvent.click(screen.getByRole("button", { name: "Check feedback" }))
    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/jobs/42/poll_feedback",
        expect.objectContaining({ method: "POST", credentials: "same-origin" })
      )
    })
    expect(await screen.findByText("Checking PR feedback now...")).toBeInTheDocument()

    fireEvent.click(screen.getByRole("button", { name: "Workflows (1)" }))
    expect(await screen.findByText("Workflow #5")).toBeInTheDocument()
    expect(screen.getByText("Run #9")).toBeInTheDocument()
  })

  it("renders the Job source browser from the app source API", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input) => {
      const path = String(input)
      if (path.startsWith("/api/v1/app/jobs/42/source?")) {
        return Promise.resolve(new Response(JSON.stringify(jobSourcePayload({ withFile: true })), { status: 200, headers: { "Content-Type": "application/json" } }))
      }
      if (path === "/api/v1/app/jobs/42/source") {
        return Promise.resolve(new Response(JSON.stringify(jobSourcePayload()), { status: 200, headers: { "Content-Type": "application/json" } }))
      }
      if (path === "/api/v1/app/jobs/42/timeline") {
        return Promise.resolve(new Response(JSON.stringify(jobTimelinePayload()), { status: 200, headers: { "Content-Type": "application/json" } }))
      }

      return Promise.resolve(new Response(JSON.stringify(jobDetailPayload()), { status: 200, headers: { "Content-Type": "application/json" } }))
    })

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/jobs/42?tab=source"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(await screen.findByText("app/models/user.rb")).toBeInTheDocument()
    fireEvent.click(screen.getByTitle("app/models/user.rb (512 B)"))

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/jobs/42/source?ref=deadbeef12345678&path=app%2Fmodels%2Fuser.rb",
        expect.objectContaining({ credentials: "same-origin" })
      )
    })
    expect(await screen.findByText(/class User/)).toBeInTheDocument()
  })

  it("dispatches Job header commands through the app API", async () => {
    vi.spyOn(window, "confirm").mockReturnValue(true)
    const commandPaths = new Map([
      ["/api/v1/app/jobs/42/start", "Initial workflow enqueued."],
      ["/api/v1/app/jobs/42/rebase", "Rebase workflow enqueued."],
      ["/api/v1/app/jobs/42/check_mergeability", "Checking mergeability now..."],
      ["/api/v1/app/jobs/42/run_again", "Retry workflow enqueued."],
      ["/api/v1/app/jobs/42/restart", "Started over."],
      ["/api/v1/app/jobs/42/approve", "Job approved."],
      ["/api/v1/app/jobs/42/unapprove", "Job unapproved."],
      ["/api/v1/app/jobs/42/cancel", "Cancellation requested."],
      ["/api/v1/app/jobs/42/reopen", "Thread reopened."],
      ["/api/v1/app/jobs/42/mark_valid", "Job marked valid and re-queued."],
      ["/api/v1/app/jobs/42/pin", "Job unpinned."]
    ])
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input, init) => {
      const path = String(input)
      if (commandPaths.has(path)) {
        return Promise.resolve(new Response(JSON.stringify({ message: commandPaths.get(path) }), { status: 200, headers: { "Content-Type": "application/json" } }))
      }
      if (path === "/api/v1/app/jobs/42/timeline") {
        return Promise.resolve(new Response(JSON.stringify(jobTimelinePayload()), { status: 200, headers: { "Content-Type": "application/json" } }))
      }

      return Promise.resolve(new Response(JSON.stringify(jobDetailPayload({
        pinned: true,
        actions: {
          can_start: true,
          can_poll_feedback: false,
          can_rebase: true,
          can_check_mergeability: true,
          can_retry: true,
          can_restart: true,
          can_cancel: true,
          can_approve: true,
          can_unapprove: true,
          can_reopen: true,
          can_mark_valid: true
        }
      })), { status: 200, headers: { "Content-Type": "application/json" } }))
    })

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/jobs/42"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    const commands = [
      ["Start Run", "POST", "/api/v1/app/jobs/42/start"],
      ["Rebase now", "POST", "/api/v1/app/jobs/42/rebase"],
      ["Check mergeability", "POST", "/api/v1/app/jobs/42/check_mergeability"],
      ["Retry", "POST", "/api/v1/app/jobs/42/run_again"],
      ["Start over", "POST", "/api/v1/app/jobs/42/restart"],
      ["Approve", "POST", "/api/v1/app/jobs/42/approve"],
      ["Unapprove", "POST", "/api/v1/app/jobs/42/unapprove"],
      ["Cancel", "POST", "/api/v1/app/jobs/42/cancel"],
      ["Reopen", "POST", "/api/v1/app/jobs/42/reopen"],
      ["Mark valid", "POST", "/api/v1/app/jobs/42/mark_valid"],
      ["Unpin", "DELETE", "/api/v1/app/jobs/42/pin"]
    ]

    expect(await screen.findByRole("button", { name: "Start Run" })).toBeInTheDocument()
    for (const [label, method, path] of commands) {
      fireEvent.click(screen.getByRole("button", { name: label }))
      await waitFor(() => {
        expect(fetchSpy).toHaveBeenCalledWith(path, expect.objectContaining({ method }))
      })
    }
  })

  it("dispatches Job metadata controls through the app API", async () => {
    vi.spyOn(window, "confirm").mockReturnValue(true)
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input, init) => {
      const path = String(input)
      if (path === "/api/v1/app/jobs/42/tags" && init?.method === "POST") {
        return Promise.resolve(new Response(JSON.stringify({ message: "Tag added." }), { status: 200, headers: { "Content-Type": "application/json" } }))
      }
      if (path === "/api/v1/app/jobs/42/tags/4" && init?.method === "DELETE") {
        return Promise.resolve(new Response(JSON.stringify({ message: "Tag removed." }), { status: 200, headers: { "Content-Type": "application/json" } }))
      }
      if (path === "/api/v1/app/jobs/42/stack_base" && init?.method === "PATCH") {
        return Promise.resolve(new Response(JSON.stringify({ message: "Stack base updated." }), { status: 200, headers: { "Content-Type": "application/json" } }))
      }
      if (path === "/api/v1/app/jobs/42/dependencies" && init?.method === "POST") {
        return Promise.resolve(new Response(JSON.stringify({ message: "Dependency added." }), { status: 200, headers: { "Content-Type": "application/json" } }))
      }
      if (path === "/api/v1/app/jobs/42/dependencies/9" && init?.method === "DELETE") {
        return Promise.resolve(new Response(JSON.stringify({ message: "Dependency removed." }), { status: 200, headers: { "Content-Type": "application/json" } }))
      }
      if (path === "/api/v1/app/jobs/42/dependencies/override" && init?.method === "POST") {
        return Promise.resolve(new Response(JSON.stringify({ message: "Dependency gate overridden." }), { status: 200, headers: { "Content-Type": "application/json" } }))
      }
      if (path === "/api/v1/app/jobs/42/timeline") {
        return Promise.resolve(new Response(JSON.stringify(jobTimelinePayload()), { status: 200, headers: { "Content-Type": "application/json" } }))
      }

      return Promise.resolve(new Response(JSON.stringify(jobDetailPayload({
        actions: { can_override_dependencies: true },
        dependencies: [
          {
            id: 9,
            source: "manual",
            manual: true,
            pending: false,
            succeeded: false,
            unresolved_slug: null,
            depends_on_job: {
              id: 41,
              kind: "issue",
              state: "open",
              summary_state: "open",
              repository_slug: "acme/widgets",
              issue_number: 11,
              issue_title: "Build hill",
              branch_name: "syrus/issue-11",
              pr_number: null,
              job_path: "/jobs/41"
            }
          }
        ],
        unsatisfied_dependencies: [
          {
            id: 9,
            source: "manual",
            manual: true,
            pending: false,
            succeeded: false,
            unresolved_slug: null,
            depends_on_job: {
              id: 41,
              kind: "issue",
              state: "open",
              summary_state: "open",
              repository_slug: "acme/widgets",
              issue_number: 11,
              issue_title: "Build hill",
              branch_name: "syrus/issue-11",
              pr_number: null,
              job_path: "/jobs/41"
            }
          }
        ]
      })), { status: 200, headers: { "Content-Type": "application/json" } }))
    })

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/jobs/42"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    fireEvent.change(await screen.findByPlaceholderText("Add tag"), { target: { value: "urgent" } })
    fireEvent.click(screen.getAllByRole("button", { name: "Add" })[0])
    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/jobs/42/tags",
        expect.objectContaining({ method: "POST", body: JSON.stringify({ tag_name: "urgent" }) })
      )
    })

    fireEvent.click(screen.getByTitle("Remove priority:forum"))
    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith("/api/v1/app/jobs/42/tags/4", expect.objectContaining({ method: "DELETE" }))
    })

    fireEvent.change(screen.getByDisplayValue("auto"), { target: { value: "main" } })
    fireEvent.click(screen.getByRole("button", { name: "Update" }))
    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/jobs/42/stack_base",
        expect.objectContaining({ method: "PATCH", body: JSON.stringify({ stack_base: "main" }) })
      )
    })

    fireEvent.change(screen.getByLabelText("Dependency"), { target: { value: "issue:3:11" } })
    fireEvent.click(screen.getAllByRole("button", { name: "Add" })[1])
    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/jobs/42/dependencies",
        expect.objectContaining({ method: "POST", body: JSON.stringify({ dependency_target: "issue:3:11" }) })
      )
    })

    fireEvent.click(screen.getByRole("button", { name: "Remove" }))
    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith("/api/v1/app/jobs/42/dependencies/9", expect.objectContaining({ method: "DELETE" }))
    })

    fireEvent.click(screen.getByRole("button", { name: "Override and force-run" }))
    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith("/api/v1/app/jobs/42/dependencies/override", expect.objectContaining({ method: "POST" }))
    })
  })

  it("dispatches Job workflow and run commands through the app API", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input, init) => {
      const path = String(input)
      if (path === "/api/v1/app/jobs/42/workflows/5/retry_step" && init?.method === "POST") {
        return Promise.resolve(new Response(JSON.stringify({ message: "Retrying implement for workflow #5..." }), { status: 200, headers: { "Content-Type": "application/json" } }))
      }
      if (path === "/api/v1/app/jobs/42/workflows/5/push_commits" && init?.method === "POST") {
        return Promise.resolve(new Response(JSON.stringify({ message: "Pushing commits to GitHub..." }), { status: 200, headers: { "Content-Type": "application/json" } }))
      }
      if (path === "/api/v1/app/jobs/42/runs/9/stop" && init?.method === "POST") {
        return Promise.resolve(new Response(JSON.stringify({ message: "Run stopped." }), { status: 200, headers: { "Content-Type": "application/json" } }))
      }
      if (path === "/api/v1/app/jobs/42/runs/9/diagnose" && init?.method === "POST") {
        return Promise.resolve(new Response(JSON.stringify({ message: "Diagnostic queued." }), { status: 200, headers: { "Content-Type": "application/json" } }))
      }
      if (path === "/api/v1/app/jobs/42/resume" && init?.method === "POST") {
        return Promise.resolve(new Response(JSON.stringify({ message: "Resume workflow enqueued." }), { status: 200, headers: { "Content-Type": "application/json" } }))
      }

      return Promise.resolve(new Response(JSON.stringify(jobDetailPayload({
        workflows: [
          {
            ...jobDetailPayload().workflows[0],
            state: "failed",
            cleaned_up_at: null,
            retry_available: true,
            steps: [
              {
                ...jobDetailPayload().workflows[0].steps[0],
                state: "failed",
                runs: [
                  {
                    ...jobDetailPayload().workflows[0].steps[0].runs[0],
                    state: "failed",
                    can_stop: true,
                    can_diagnose: true,
                    can_resume: true
                  }
                ]
              }
            ]
          }
        ]
      })), { status: 200, headers: { "Content-Type": "application/json" } }))
    })

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/jobs/42?tab=workflows"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(await screen.findByText("Workflow #5")).toBeInTheDocument()
    const commands = [
      ["Retry failed step", "POST", "/api/v1/app/jobs/42/workflows/5/retry_step"],
      ["Push commits", "POST", "/api/v1/app/jobs/42/workflows/5/push_commits"],
      ["Stop", "POST", "/api/v1/app/jobs/42/runs/9/stop"],
      ["Diagnose", "POST", "/api/v1/app/jobs/42/runs/9/diagnose"]
    ]
    for (const [label, method, path] of commands) {
      fireEvent.click(screen.getByRole("button", { name: label }))
      await waitFor(() => {
        expect(fetchSpy).toHaveBeenCalledWith(path, expect.objectContaining({ method }))
      })
    }

    fireEvent.click(screen.getByRole("button", { name: "Resume" }))
    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/jobs/42/resume",
        expect.objectContaining({ method: "POST", body: JSON.stringify({ source_run_id: 9 }) })
      )
    })
  })

  it("adds and removes Job attachments through the app API", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input, init) => {
      const path = String(input)
      if (path === "/api/v1/app/jobs/42/attachments" && init?.method === "POST") {
        return Promise.resolve(new Response(JSON.stringify({ message: "Attachment added." }), { status: 200, headers: { "Content-Type": "application/json" } }))
      }
      if (path === "/api/v1/app/jobs/42/attachments/8" && init?.method === "DELETE") {
        return Promise.resolve(new Response(JSON.stringify({ message: "Attachment removed." }), { status: 200, headers: { "Content-Type": "application/json" } }))
      }

      return Promise.resolve(new Response(JSON.stringify(jobDetailPayload()), { status: 200, headers: { "Content-Type": "application/json" } }))
    })

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/jobs/42?tab=attachments"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    const file = new File(["notes"], "notes.md", { type: "text/markdown" })
    fireEvent.change(await screen.findByLabelText("Files"), { target: { files: [file] } })
    fireEvent.change(screen.getByLabelText("Google Doc URL"), { target: { value: "https://docs.google.com/document/d/context/edit" } })
    fireEvent.click(within(screen.getByRole("heading", { name: "Add attachment" }).closest("form")!).getByRole("button", { name: "Add" }))

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/jobs/42/attachments",
        expect.objectContaining({ method: "POST", body: expect.any(FormData) })
      )
    })
    const formData = fetchSpy.mock.calls.find(([path, init]) => path === "/api/v1/app/jobs/42/attachments" && init?.method === "POST")?.[1]?.body as FormData
    expect(formData.get("job_attachment[google_doc_url]")).toBe("https://docs.google.com/document/d/context/edit")
    expect(formData.get("job_attachment[files][]")).toBe(file)

    fireEvent.click(screen.getByRole("button", { name: "Remove" }))
    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith("/api/v1/app/jobs/42/attachments/8", expect.objectContaining({ method: "DELETE" }))
    })
  })

  it("renders a chat and sends a message from the app API", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input, init) => {
      const path = String(input)
      if (path === "/api/v1/app/chats/8/message" && init?.method === "POST") {
        return Promise.resolve(new Response(JSON.stringify(chatPayload({
          message: "Message sent.",
          messages: [
            ...chatPayload().messages,
            {
              type: "message",
              id: 10,
              role: "user",
              text: "Now inspect proposals",
              bookmarkable: true,
              bookmark_path: "/chats/8/bookmarks"
            }
          ],
          turnInFlight: true
        })), { status: 200, headers: { "Content-Type": "application/json" } }))
      }

      return Promise.resolve(new Response(JSON.stringify(chatPayload()), { status: 200, headers: { "Content-Type": "application/json" } }))
    })

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/chats/8"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(await screen.findByRole("main", { name: "Chat" })).toBeInTheDocument()
    expect(await screen.findByText("Discuss aqueducts.")).toBeInTheDocument()
    expect(screen.getByText("Aqueducts")).toBeInTheDocument()
    expect(screen.getByText("Launch notes")).toBeInTheDocument()
    expect(screen.getByText("Version 2")).toBeInTheDocument()
    expect(screen.getByText("12.4k in", { exact: false })).toBeInTheDocument()
    fireEvent.change(screen.getByPlaceholderText("Ask about this repository..."), { target: { value: "Now inspect proposals" } })
    fireEvent.click(screen.getByRole("button", { name: "Send" }))

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/chats/8/message",
        expect.objectContaining({
          method: "POST",
          credentials: "same-origin",
          body: JSON.stringify({ chat_message: { text: "Now inspect proposals" } })
        })
      )
    })
    expect(await screen.findByText("Message sent.")).toBeInTheDocument()
    expect(screen.getByText("Now inspect proposals")).toBeInTheDocument()
  })

  it("saves chat whiteboard changes through the app API", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input, init) => {
      const path = String(input)
      if (path === "/api/v1/app/chats/8/whiteboard" && init?.method === "PATCH") {
        return Promise.resolve(new Response(JSON.stringify({
          scene_json: { elements: [{ id: "shape-react", version: 1 }] },
          version: 3
        }), { status: 200, headers: { "Content-Type": "application/json" } }))
      }

      return Promise.resolve(new Response(JSON.stringify(chatPayload()), { status: 200, headers: { "Content-Type": "application/json" } }))
    })

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/chats/8"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    fireEvent.click(await screen.findByRole("button", { name: "Draw on whiteboard" }))

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/chats/8/whiteboard",
        expect.objectContaining({
          method: "PATCH",
          credentials: "same-origin",
          body: JSON.stringify({
            elements: [{ id: "box-1", type: "rectangle" }, { id: "shape-react", version: 1 }],
            expected_version: 2
          })
        })
      )
    })
    expect(await screen.findByText("Version 3")).toBeInTheDocument()
  })

  it("renders raw chat messages on the frontend", async () => {
    vi.spyOn(window, "fetch").mockResolvedValue(
      new Response(JSON.stringify(chatPayload({
        messages: [
          {
            type: "message",
            id: 10,
            role: "tool_use",
            tool_name: "Read",
            content: { input: { file_path: "app/models/chat.rb" } },
            text: "",
            bookmarkable: false,
            bookmark_path: "/chats/8/bookmarks"
          },
          {
            type: "message",
            id: 11,
            role: "tool_result",
            tool_name: "Read",
            content: { result: [{ type: "text", text: "class Chat\nend" }] },
            text: "",
            bookmarkable: false,
            bookmark_path: "/chats/8/bookmarks"
          },
          {
            type: "message",
            id: 12,
            role: "system",
            tool_name: null,
            content: { text: "[result] subtype=success, is_error=false, turns=4, duration_ms=170223, total_cost_usd=0.37236969999999997" },
            text: "[result] subtype=success, is_error=false, turns=4, duration_ms=170223, total_cost_usd=0.37236969999999997",
            bookmarkable: false,
            bookmark_path: "/chats/8/bookmarks"
          }
        ]
      })), { status: 200, headers: { "Content-Type": "application/json" } })
    )

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/chats/8"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(await screen.findByText("Read")).toBeInTheDocument()
    expect(screen.getAllByText("app/models/chat.rb").length).toBeGreaterThan(0)
    expect(screen.getByText(/class Chat\s+end/)).toBeInTheDocument()
    expect(screen.getByText(/Agent run succeeded/)).toBeInTheDocument()
    expect(screen.getByText(/\$0\.37/)).toBeInTheDocument()
  })

  it("runs chat commands through the app API", async () => {
    const search = "?attachment_type=Repository&attachment_query=tools"
    const proposalMessage = {
      type: "message",
      id: 10,
      role: "assistant",
      text: "Proposal proposed.",
      bookmarkable: true,
      bookmark_path: "/chats/8/bookmarks",
      proposal: {
        id: 5,
        kind: "syrus_issue",
        kind_label: "Syrus issue",
        state: "proposed",
        state_label: "Proposed",
        title: "Map auth",
        slug: "auth-map",
        body: "Map the auth flow.",
        proposed: true,
        resolved: false,
        epic_bundle: false,
        scoped_repository_slug: "acme/widgets",
        dependencies: [],
        target_epic_label: null,
        confirm_path: "/chats/8/proposals/5/confirm",
        reject_path: "/chats/8/proposals/5/reject",
        app_confirm_path: "/api/v1/app/chats/8/proposals/5/confirm",
        app_reject_path: "/api/v1/app/chats/8/proposals/5/reject",
        materialized_label: null,
        materialized_path: null
      }
    }
    const initialPayload = {
      ...chatPayload({ messages: [...chatPayload().messages, proposalMessage] }),
      attachment_results: [{ type: "Repository", id: 4, label: "acme/tools" }],
      pending_actions: [
        {
          id: 7,
          label: "Cancel Job #44",
          action: "cancel_job",
          action_type: null,
          app_confirm_path: "/api/v1/app/chats/8/pending_actions/7/confirm",
          app_cancel_path: "/api/v1/app/chats/8/pending_actions/7"
        }
      ]
    }
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input, init) => {
      const path = String(input)
      if (path === `/api/v1/app/chats/8/bookmarks${search}` && init?.method === "POST") {
        return Promise.resolve(new Response(JSON.stringify({
          ...initialPayload,
          message: "Bookmarked Aqueduct marker.",
          bookmarks: [...initialPayload.bookmarks, { id: 2, label: "Aqueduct marker", chat_message_id: 9 }]
        }), { status: 200, headers: { "Content-Type": "application/json" } }))
      }

      if (path === `/api/v1/app/chats/8/attachments${search}` && init?.method === "POST") {
        return Promise.resolve(new Response(JSON.stringify({
          ...initialPayload,
          message: "acme/tools attached.",
          attachment_groups: {
            ...initialPayload.attachment_groups,
            repositories: [
              ...initialPayload.attachment_groups.repositories,
              { id: 4, label: "acme/tools", detach_path: "/chats/8/attachments/4", app_detach_path: "/api/v1/app/chats/8/attachments/4" }
            ]
          },
          attachment_results: []
        }), { status: 200, headers: { "Content-Type": "application/json" } }))
      }

      if (path === `/api/v1/app/chats/8/attachments/2${search}` && init?.method === "DELETE") {
        return Promise.resolve(new Response(JSON.stringify({
          ...initialPayload,
          message: "acme/widgets detached.",
          attachment_groups: { ...initialPayload.attachment_groups, repositories: [] }
        }), { status: 200, headers: { "Content-Type": "application/json" } }))
      }

      if (path === `/api/v1/app/chats/8/proposals/5/confirm${search}` && init?.method === "POST") {
        return Promise.resolve(new Response(JSON.stringify({
          ...initialPayload,
          message: "Proposal confirmed and filed as Job #88.",
          messages: [initialPayload.messages[0], {
            ...proposalMessage,
            proposal: { ...proposalMessage.proposal, proposed: false, state: "confirmed", state_label: "Confirmed", materialized_label: "Job #88", materialized_path: "/jobs/88" }
          }]
        }), { status: 200, headers: { "Content-Type": "application/json" } }))
      }

      if (path === `/api/v1/app/chats/8/pending_actions/7/confirm${search}` && init?.method === "POST") {
        return Promise.resolve(new Response(JSON.stringify({
          ...initialPayload,
          message: "Pending action confirmed.",
          pending_actions: []
        }), { status: 200, headers: { "Content-Type": "application/json" } }))
      }

      return Promise.resolve(new Response(JSON.stringify(initialPayload), { status: 200, headers: { "Content-Type": "application/json" } }))
    })

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={[`/app-shell/chats/8${search}`]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(await screen.findByText("Map auth")).toBeInTheDocument()
    fireEvent.click(screen.getAllByRole("button", { name: "Bookmark" })[0])
    fireEvent.change(screen.getByLabelText("Label"), { target: { value: "Aqueduct marker" } })
    fireEvent.click(screen.getByRole("button", { name: "Save" }))
    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        `/api/v1/app/chats/8/bookmarks${search}`,
        expect.objectContaining({
          method: "POST",
          body: JSON.stringify({ message_id: 9, chat_bookmark: { label: "Aqueduct marker" } })
        })
      )
    })

    fireEvent.click(await screen.findByText("acme/tools"))
    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        `/api/v1/app/chats/8/attachments${search}`,
        expect.objectContaining({
          method: "POST",
          body: JSON.stringify({ attachable_type: "Repository", attachable_id: 4 })
        })
      )
    })

    fireEvent.click(screen.getByTitle("Detach acme/widgets"))
    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        `/api/v1/app/chats/8/attachments/2${search}`,
        expect.objectContaining({ method: "DELETE" })
      )
    })

    fireEvent.click(screen.getAllByRole("button", { name: "Confirm" })[1])
    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        `/api/v1/app/chats/8/proposals/5/confirm${search}`,
        expect.objectContaining({ method: "POST" })
      )
    })

    fireEvent.click(screen.getByRole("button", { name: "Confirm" }))
    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        `/api/v1/app/chats/8/pending_actions/7/confirm${search}`,
        expect.objectContaining({ method: "POST" })
      )
    })
  })

  it("loads older chat messages from the app API", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input) => {
      const path = String(input)
      if (path === "/api/v1/app/chats/8/messages?before=9") {
        return Promise.resolve(new Response(JSON.stringify({
          has_more_older: false,
          messages: [
            {
              type: "message",
              id: 4,
              role: "assistant",
              text: "Earlier **aqueduct** note.",
              bookmarkable: true,
              bookmark_path: "/chats/8/bookmarks"
            }
          ]
        }), { status: 200, headers: { "Content-Type": "application/json" } }))
      }

      return Promise.resolve(new Response(JSON.stringify(chatPayload({ hasMoreOlder: true })), { status: 200, headers: { "Content-Type": "application/json" } }))
    })

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/chats/8"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    fireEvent.click(await screen.findByRole("button", { name: "Load older messages" }))

    expect(await screen.findByText("aqueduct")).toBeInTheDocument()
    expect(fetchSpy).toHaveBeenCalledWith(
      "/api/v1/app/chats/8/messages?before=9",
      expect.objectContaining({
        credentials: "same-origin",
        headers: { Accept: "application/json" }
      })
    )
  })

  it("renders the new chat route and posts to the app API", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockImplementation((input, init) => {
      const path = String(input)
      if (path === "/api/v1/app/chats" && init?.method === "POST") {
        return Promise.resolve(new Response(
          JSON.stringify({ error: { code: "validation_failed", message: "Repository is not available." } }),
          { status: 422, headers: { "Content-Type": "application/json" } }
        ))
      }

      return Promise.resolve(new Response(JSON.stringify(chatFormPayload()), { status: 200, headers: { "Content-Type": "application/json" } }))
    })

    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={["/app-shell/chats/new"]}>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )

    expect(await screen.findByRole("main", { name: "New chat" })).toBeInTheDocument()
    fireEvent.change(await screen.findByLabelText("Repository"), { target: { value: "3" } })
    fireEvent.change(screen.getByLabelText("First message"), { target: { value: "Map the forum" } })
    fireEvent.click(screen.getByRole("button", { name: "Create chat" }))

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/v1/app/chats",
        expect.objectContaining({
          method: "POST",
          credentials: "same-origin",
          body: JSON.stringify({ repository_id: "3", chat_message: { text: "Map the forum" } })
        })
      )
    })
    expect(await screen.findByText("Repository is not available.")).toBeInTheDocument()
  })
})

function bootstrapPayload() {
  return {
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
  }
}

function scheduledTaskOptions() {
  return {
    kinds: ["cron", "one_shot"],
    pr_pileup_policies: ["skip", "pile", "replace"],
    auto_approve_modes: [
      { value: "never", label: "Never", preview: "No direct rule; Jobs can still inherit a repository or user default." },
      { value: "if_graders_pass", label: "If graders pass", preview: "Jobs using this rule enter landing after repo-committed graders pass." }
    ]
  }
}

function scheduledTaskDetailPayload(overrides: { state?: string; message?: string } = {}) {
  return {
    task: {
      id: 12,
      name: "Weekly tests",
      kind: "cron",
      state: overrides.state || "scheduled",
      repository: { id: 3, slug: "acme/widgets", repository_path: "/repositories/3" },
      schedule_label: "17 9 * * 1",
      last_fired_at: null,
      archived_at: null,
      consecutive_failure_count: 0,
      scheduled_task_path: "/scheduled_tasks/12",
      prompt: "Keep tests moving.",
      cron_expression: "0 9 * * 1",
      hourly_cron_expression: "17 9 * * 1",
      fire_at: null,
      next_fire_at: "2026-05-31T09:17:00Z",
      pr_pileup_policy: "skip",
      auto_approve_mode: "never",
      auto_approve_preview: "No direct rule; Jobs can still inherit a repository or user default.",
      last_successful_fire_at: null,
      archived: false,
      fireable: true,
      pausable: overrides.state !== "paused",
      resumable: overrides.state === "paused",
      editable: true
    },
    recent_jobs: [
      {
        id: 44,
        state: "open",
        closure_reason: null,
        pr_number: 101,
        external_pr_number: null,
        created_at: "2026-05-30T12:00:00Z",
        job_path: "/jobs/44"
      }
    ],
    options: scheduledTaskOptions(),
    message: overrides.message
  }
}

function repositoryScheduledTasksPayload(overrides: { state?: string; active?: boolean; message?: string } = {}) {
  const detail = scheduledTaskDetailPayload({ state: overrides.state || "scheduled" }).task
  return {
    repository: { id: 3, slug: "acme/widgets", repository_path: "/repositories/3" },
    tasks: [
      {
        ...detail,
        name: "Daily review",
        prompt: "Review the project.",
        active: overrides.active ?? true
      }
    ],
    new_scheduled_task_path: "/repositories/3/scheduled_tasks/new",
    options: scheduledTaskOptions(),
    message: overrides.message
  }
}

function credentialsPayload(overrides: {
  name?: string
  apiToken?: boolean
  newApiToken?: string
  message?: string
  documents?: Array<Record<string, unknown>>
} = {}) {
  return {
    user: {
      id: 1,
      email_address: "operator@example.com",
      name: overrides.name ?? "Operator",
      display_name: overrides.name ?? "Operator",
      github_handle: "operator",
      admin: true,
      agent_provider: "claude",
      codex_auth_mode: "api_key",
      agent_max_turns: 200,
      scheduling_paused: false,
      auto_approve_mode: "never"
    },
    credential_status: {
      github_token: true,
      claude_oauth_token: true,
      codex_api_key: false,
      codex_auth_json: false,
      api_token: overrides.apiToken ?? false
    },
    github_rate_limit: {
      remaining: 4999,
      limit: 5000,
      resource: "core",
      reset_at: "2026-05-30T13:00:00Z",
      observed_at: "2026-05-30T12:00:00Z"
    },
    documents: overrides.documents || [],
    options: {
      agent_providers: ["claude", "codex"],
      codex_auth_modes: ["api_key", "chatgpt_login"],
      agent_max_turns: { min: 0, max: 1000 },
      clearable_credentials: [
        { value: "github_token", label: "GitHub token" },
        { value: "claude_oauth_token", label: "Claude OAuth token" }
      ],
      auto_approve_modes: [
        { value: "never", label: "Never", preview: "No direct rule; Jobs can still inherit a repository or user default." },
        { value: "if_graders_pass", label: "If graders pass", preview: "Jobs using this rule enter landing after repo-committed graders pass." }
      ]
    },
    message: overrides.message,
    new_api_token: overrides.newApiToken
  }
}

function repositoryDocumentsPayload(overrides: {
  documents?: Array<Record<string, unknown>>
  message?: string
} = {}) {
  return {
    repository: { id: 3, slug: "acme/widgets", repository_path: "/repositories/3" },
    documents: overrides.documents || [],
    accepted_file_content_types: ["text/markdown", "application/pdf", "image/png"],
    message: overrides.message
  }
}

function directJobFormPayload() {
  return {
    repositories: [
      {
        id: 3,
        slug: "acme/widgets",
        repository_path: "/repositories/3",
        default_agent_provider: "codex",
        default_agent_provider_label: "Codex"
      }
    ],
    configured_agent_providers: [
      { value: "claude", label: "Claude Code" },
      { value: "codex", label: "Codex" }
    ],
    selected_repository_id: "3",
    selected_agent_provider: null,
    create_more: true,
    prompt_templates: [
      {
        id: "configure-syrus-prep",
        name: "Configure Syrus build dependencies",
        description: "Detect package managers and write .syrus.yml.",
        prompt: "Write a .syrus.yml setup file."
      }
    ],
    priorities: [
      { value: "high", label: "High", description: "Runs before medium and low" },
      { value: "medium", label: "Medium", description: "Default" },
      { value: "low", label: "Low", description: "Yields to higher-priority jobs" }
    ],
    accepted_file_content_types: ["text/markdown", "application/pdf", "image/png"],
    new_repository_path: "/repositories/new",
    dashboard_jobs_path: "/dashboard/jobs"
  }
}

function repositoriesPayload(overrides: { message?: string } = {}) {
  return {
    active_repositories: [
      {
        id: 3,
        slug: "acme/widgets",
        owner: "acme",
        name: "widgets",
        default_branch: "main",
        trigger_label: "syrus",
        polling_enabled: true,
        archived: false,
        archived_at: null,
        agent_provider: "codex",
        agent_provider_label: "Codex",
        last_poll_status: "ok",
        last_poll_started_at: "2026-05-30T12:00:00Z",
        last_poll_error: null,
        repository_path: "/repositories/3",
        edit_repository_path: "/repositories/3/edit"
      }
    ],
    archived_repositories: [
      {
        id: 4,
        slug: "old/repo",
        owner: "old",
        name: "repo",
        default_branch: "main",
        trigger_label: "syrus",
        polling_enabled: false,
        archived: true,
        archived_at: "2026-05-29T12:00:00Z",
        agent_provider: null,
        agent_provider_label: "default",
        last_poll_status: null,
        last_poll_started_at: null,
        last_poll_error: null,
        repository_path: "/repositories/4",
        edit_repository_path: "/repositories/4/edit"
      }
    ],
    new_repository_path: "/repositories/new",
    message: overrides.message
  }
}

function repositoryFormPayload(overrides: Partial<{
  repository: Record<string, unknown>
}> = {}) {
  return {
    repository: overrides.repository || {
      id: null,
      owner: "",
      name: "",
      slug: null,
      default_branch: "main",
      trigger_label: "syrus",
      polling_enabled: true,
      prepare_enabled: true,
      pr_cost_footer_enabled: true,
      auto_merge_enabled: false,
      agent_provider: "",
      auto_approve_mode: "never",
      github_owner_id: null,
      github_repository_id: null,
      repository_path: null
    },
    configured_agent_providers: [
      { value: "claude", label: "Claude Code" },
      { value: "codex", label: "Codex" }
    ],
    user_agent_provider_label: "Claude Code",
    auto_approve_modes: [
      { value: "never", label: "Never", preview: "No direct rule; Jobs can still inherit a repository or user default." },
      { value: "if_graders_pass", label: "If graders pass", preview: "Jobs using this rule enter landing after repo-committed graders pass." },
      { value: "if_graders_pass_and_tagged_safe", label: "If graders pass and tagged safe", preview: "Jobs using this rule also need the safe tag before landing." }
    ],
    repositories_path: "/repositories"
  }
}

function repositoryDetailPayload() {
  return {
    message: null,
    repository: {
      id: 3,
      slug: "acme/widgets",
      owner: "acme",
      name: "widgets",
      default_branch: "main",
      trigger_label: "syrus",
      polling_enabled: true,
      archived: false,
      agent_provider: "codex",
      agent_provider_label: "Codex",
      effective_agent_provider: "codex",
      effective_agent_provider_label: "Codex",
      github_url: "https://github.com/acme/widgets",
      created_at: "2026-05-30T12:00:00Z",
      owner_user: {
        email_address: "operator@example.com",
        admin: true
      },
      github_rate_limit: {
        remaining: 4990,
        limit: 5000,
        resource: "core",
        observed_at: "2026-05-30T12:00:00Z"
      }
    },
    tabs: [
      { key: "overview", label: "Overview", path: "/repositories/3" },
      { key: "github_issues", label: "GitHub Issues", path: "/repositories/3?tab=github_issues" },
      { key: "scheduled_tasks", label: "Scheduled Tasks", path: "/repositories/3/scheduled_tasks" }
    ],
    counts: {
      running: 1,
      queued: 1,
      failed_7d: 1
    },
    retry_failed_jobs: {
      count: 1,
      agent_provider: "codex",
      agent_provider_label: "Codex"
    },
    credential_status: {
      mode: "pat",
      label: "PAT fallback",
      installation_account: null,
      github_app_registered: true,
      install_url: "https://github.com/apps/operator-syrus/installations/new/permissions?target_id=100&repository_ids[]=200",
      register_path: null,
      previous_installation_removed: false,
      missing_github_ids: false
    },
    notes: [
      {
        id: 11,
        body: "Repository note pinned.",
        author: "operator",
        created_at: "2026-05-30T12:00:00Z",
        delete_path: "/repositories/3/notes/11",
        app_delete_path: "/api/v1/app/repositories/3/notes/11"
      }
    ],
    jobs: [
      {
        id: 44,
        state: "open",
        priority: "high",
        issue_number: 1,
        issue_title: "Fix forum",
        job_path: "/jobs/44",
        source: {
          label: "#1",
          path: "https://github.com/acme/widgets/issues/1",
          external: true
        },
        pr_number: 12,
        pr_url: "https://github.com/acme/widgets/pull/12",
        external_pr_number: null,
        external_pr_url: null,
        current_step_caption: "currently: Implement (workflow: Initial)",
        runs_count: 2,
        updated_at: "2026-05-30T12:00:00Z"
      }
    ],
    pagination: {
      page: 1,
      per_page: 20,
      total_jobs: 1,
      total_pages: 1,
      first_item: 1,
      last_item: 1,
      previous_path: null,
      next_path: null
    },
    paths: {
      new_job_path: "/jobs/new?repository_id=3",
      edit_repository_path: "/repositories/3/edit",
      poll_repository_path: "/repositories/3/poll",
      archive_repository_path: "/repositories/3/archive",
      retry_failed_jobs_repository_path: "/repositories/3/retry_failed_jobs",
      app_poll_repository_path: "/api/v1/app/repositories/3/poll",
      app_archive_repository_path: "/api/v1/app/repositories/3/archive",
      app_retry_failed_jobs_repository_path: "/api/v1/app/repositories/3/retry_failed_jobs",
      repository_notes_path: "/repositories/3/notes",
      app_repository_notes_path: "/api/v1/app/repositories/3/notes",
      repositories_path: "/repositories",
      repository_documents_path: "/repositories/3/documents",
      repository_scheduled_tasks_path: "/repositories/3/scheduled_tasks"
    }
  }
}

function repositoryIssuesPayload(overrides: { message?: string; delegated?: boolean } = {}) {
  const detail = repositoryDetailPayload()
  return {
    message: overrides.message || null,
    error_message: null,
    repository: detail.repository,
    tabs: detail.tabs,
    state: "open",
    issue_count: 1,
    issues: [
      {
        number: 7,
        title: "Fix the forum",
        state: "open",
        html_url: "https://github.com/acme/widgets/issues/7",
        body_excerpt: "The forum is missing tasteful columns.",
        user_login: "alice",
        created_at: "2026-05-30T12:00:00Z",
        labels: [
          { name: "bug", color: "0075ca" }
        ],
        delegated: overrides.delegated || false
      }
    ],
    state_paths: {
      open: "/repositories/3?tab=github_issues&state=open",
      closed: "/repositories/3?tab=github_issues&state=closed"
    },
    paths: {
      github_issues_path: "https://github.com/acme/widgets/issues",
      app_comment_issue_path: "/api/v1/app/repositories/3/issues/comment",
      app_close_issue_path: "/api/v1/app/repositories/3/issues/close",
      app_delegate_issue_path: "/api/v1/app/repositories/3/issues/delegate",
      app_bulk_issues_path: "/api/v1/app/repositories/3/issues/bulk"
    }
  }
}

function epicFormPayload() {
  return {
    epic: {
      id: null,
      title: "",
      description: "",
      repository_id: null,
      github_issue_url: "",
      epic_path: null
    },
    repositories: [
      {
        id: 3,
        slug: "acme/widgets"
      }
    ],
    dashboard_epics_path: "/dashboard/epics"
  }
}

function dashboardPayload(overrides: Record<string, unknown> = {}) {
  const payload = {
    subject: "job",
    view: "list",
    page: 1,
    per_page: 25,
    total: 1,
    total_pages: 1,
    counts: {
      jobs: 4,
      epics: 2,
      workflows: 6
    },
    preferences: {
      sort: { column: "created_at", direction: "desc" },
      visible_columns: ["checkbox", "issue", "state", "repository", "latest", "workflows_count", "started"],
      kanban_lanes: ["queued", "running", "succeeded"],
      raw: {}
    },
    controls: {
      views: ["list", "kanban"],
      sort_columns: ["title", "state", "repository", "created_at", "started_at"],
      sort_directions: ["asc", "desc"],
      columns: {
        required: [
          { key: "checkbox", title: "Checkbox" },
          { key: "issue", title: "Issue" }
        ],
        optional: [
          { key: "state", title: "State" },
          { key: "repository", title: "Repository" },
          { key: "latest", title: "Latest" },
          { key: "workflows_count", title: "Workflows count" },
          { key: "started", title: "Started" },
          { key: "created_at", title: "Created at" },
          { key: "updated_at", title: "Updated at" }
        ]
      },
      kanban_lanes: [
        { key: "blocked", title: "Blocked" },
        { key: "queued", title: "Queued" },
        { key: "running", title: "Running" },
        { key: "succeeded", title: "Succeeded" },
        { key: "landing", title: "Landing" },
        { key: "failed", title: "Failed" }
      ],
      filter_schema: [
        {
          field: "state",
          label: "State",
          bucket: "enum",
          operators: ["is"],
          values: [
            { value: "open", label: "Any open" },
            { value: "closed", label: "Closed or merged" }
          ]
        },
        {
          field: "repository_id",
          label: "Repository",
          bucket: "fk",
          operators: ["is"],
          values: [
            { value: 3, label: "acme/widgets" }
          ]
        },
        {
          field: "kind",
          label: "Kind",
          bucket: "enum",
          operators: ["is"],
          values: ["issue", "cron", "direct"]
        }
      ]
    },
    landing_queue: {
      visible: false,
      paused: false,
      toggle_path: "/api/v1/app/dashboard/landing_pause"
    },
    smart_folders: [
      {
        id: 7,
        name: "My work",
        kind: "custom",
        subject_type: "job",
        active: false,
        path: "/dashboard/jobs?view=list&smart_folder_id=7"
      }
    ],
    active_smart_folder_id: null,
    items: [],
    lanes: [],
    kanban_limit: null,
    paths: {
      dashboard_path: "/dashboard",
      dashboard_jobs_path: "/dashboard/jobs",
      dashboard_epics_path: "/dashboard/epics",
      dashboard_workflows_path: "/dashboard/workflows",
      app_dashboard_path: "/api/v1/app/dashboard"
    }
  }

  return {
    ...payload,
    ...overrides
  }
}

function dashboardJobItem(overrides: Record<string, unknown> = {}) {
  return {
    type: "job",
    id: 42,
    kind: "issue",
    title: "Repair aqueduct",
    state: "open",
    summary_state: "running",
    validity: "valid",
    priority: "high",
    issue_number: 12,
    branch_name: "syrus/issue-12",
    pr_number: 34,
    latest_workflow_state: "running",
    created_at: "2026-05-30T10:00:00Z",
    updated_at: "2026-05-30T12:00:00Z",
    started_at: "2026-05-30T10:01:00Z",
    finished_at: null,
    approved_at: null,
    dependencies_overridden_at: null,
    last_feedback_addressed_at: null,
    last_seen_comment_at: null,
    pr_mergeable_checked_at: null,
    workflows_count: 1,
    repository: { id: 3, slug: "acme/widgets" },
    tags: [{ id: 5, name: "urgent", color: "red" }],
    paths: { job_path: "/jobs/42", source_path: "/jobs/42/source" },
    ...overrides
  }
}

function epicDetailPayload(overrides: {
  message?: string
  state?: string
  stateTransitions?: Array<Record<string, unknown>>
} = {}) {
  return {
    message: overrides.message,
    epic: {
      id: 7,
      number: 7,
      display_number: "EPIC-7",
      title: "Raise the forum",
      description: "Build **columns**.",
      state: overrides.state || "ready",
      github_issue_url: "https://github.com/acme/widgets/issues/12",
      updated_at: "2026-05-30T12:00:00Z",
      archived: false,
      jobs_count: 1,
      epic_path: "/epics/7",
      repository: {
        id: 3,
        slug: "acme/widgets",
        repository_path: "/repositories/3"
      }
    },
    summary: {
      done_jobs_count: 1,
      total_jobs_count: 1,
      dependency_edge_count: 1,
      blocked: false
    },
    state_transitions: overrides.stateTransitions || [
      { label: "Start", target_state: "in_progress", confirm: null },
      { label: "Archive", target_state: "archived", confirm: "Archive this Epic?" }
    ],
    graph: {
      empty: false,
      definition: "flowchart LR\n  epic_7[\"EPIC-7 Raise the forum\"]\n  epic_6[\"EPIC-6 Deliver marble\"]\n  epic_7 --> epic_6",
      node_count: 2,
      epic_dependency_count: 1,
      job_blocker_count: 0,
      initially_open: true
    },
    jobs: [
      {
        id: 42,
        label: "#12",
        title: "Survey forum",
        path: "/jobs/42",
        state: "closed",
        repository_slug: "acme/widgets"
      }
    ],
    paths: {
      dashboard_epics_path: "/dashboard/epics",
      edit_epic_path: "/epics/7/edit",
      app_state_path: "/api/v1/app/epics/7/state",
      app_archive_path: "/api/v1/app/epics/7/archive"
    }
  }
}

function jobDetailPayload(overrides: Record<string, unknown> = {}) {
  const payload = {
    job: {
      id: 42,
      kind: "issue",
      state: "open",
      summary_state: "implemented",
      priority: "medium",
      validity: "valid",
      credential_mode: "pat",
      agent_provider: "codex",
      stack_base: "auto",
      issue_number: 12,
      issue_title: "Repair aqueduct",
      issue_body: "Water should climb the hill.",
      branch_name: "syrus/issue-12",
      pr_number: 77,
      pr_url: "https://github.com/acme/widgets/pull/77",
      external_pr_number: null,
      external_pr_url: null,
      pr_mergeable: true,
      pr_mergeable_checked_at: "2026-05-30T12:00:00Z",
      closure_reason: null,
      landing_failure_reason: null,
      approved_at: null,
      approved_via: null,
      total_cost_usd: 0.1234,
      billed_runs_count: 1,
      workflows_count: 1,
      runs_count: 1,
      any_active_run: false,
      prepare_skipped: false,
      prepare_skip_reason: null,
      created_at: "2026-05-30T10:00:00Z",
      updated_at: "2026-05-30T12:00:00Z",
      started_at: "2026-05-30T10:01:00Z",
      finished_at: null
    },
    repository: {
      id: 3,
      slug: "acme/widgets",
      owner: "acme",
      name: "widgets",
      default_branch: "main",
      repository_path: "/repositories/3"
    },
    pinned: false,
    tags: [{ id: 4, name: "priority:forum", color: "gray" }],
    tag_options: [{ id: 4, name: "priority:forum", color: "gray" }],
    dependencies: [],
    dependents: [],
    unsatisfied_dependencies: [],
    dependency_target_options: [{ label: "acme/widgets #11 - Build hill (Job #41)", value: "issue:3:11" }],
    attachments: [
      {
        id: 8,
        kind: "google_doc",
        attachment_type: "google_doc_link",
        title: "Hydraulic notes",
        filename: null,
        content_type: null,
        byte_size: null,
        google_doc_url: "https://docs.google.com/document/d/aqueduct/edit",
        uploaded_file: false,
        file_path: null,
        created_at: "2026-05-30T10:02:00Z",
        app_delete_path: "/api/v1/app/jobs/42/attachments/8"
      }
    ],
    summary: {
      run_id: 9,
      text: "Moved the uphill water simulation.",
      finished_at: "2026-05-30T12:00:00Z"
    },
    landing_queue_entry: null,
    workflows: [
      {
        id: 5,
        trigger_kind: "initial",
        agent_provider: "codex",
        state: "succeeded",
        failure_count: 0,
        artifacts: {},
        cleaned_up_at: null,
        retry_available: false,
        started_at: "2026-05-30T10:01:00Z",
        finished_at: "2026-05-30T12:00:00Z",
        created_at: "2026-05-30T10:00:00Z",
        updated_at: "2026-05-30T12:00:00Z",
        app_retry_step_path: "/api/v1/app/jobs/42/workflows/5/retry_step",
        app_push_commits_path: "/api/v1/app/jobs/42/workflows/5/push_commits",
        steps: [
          {
            id: 6,
            kind: "implement",
            position: 1,
            iteration: null,
            loop_id: null,
            state: "succeeded",
            started_at: "2026-05-30T10:01:00Z",
            finished_at: "2026-05-30T12:00:00Z",
            created_at: "2026-05-30T10:00:00Z",
            updated_at: "2026-05-30T12:00:00Z",
            details: null,
            latest: true,
            runs: [
              {
                id: 9,
                state: "succeeded",
                trigger_kind: "initial",
                agent_provider: "codex",
                agent_outcome: "success",
                agent_turns: 4,
                agent_pr_title: "Repair aqueduct",
                agent_summary: "Moved the uphill water simulation.",
                parent_session_id: null,
                head_sha: "deadbeef",
                iteration: null,
                started_at: "2026-05-30T10:01:00Z",
                last_heartbeat_at: "2026-05-30T11:59:00Z",
                finished_at: "2026-05-30T12:00:00Z",
                created_at: "2026-05-30T10:00:00Z",
                updated_at: "2026-05-30T12:00:00Z",
                cost_usd: 0.1234,
                input_tokens: 1200,
                output_tokens: 300,
                agent_diff_present: true,
                agent_diff_bytes: 2048,
                job_log_count: 12,
                rate_limited: false,
                run_diagnostic: null,
                health_snapshots: [],
                agent_session: { session_id: "session-9", provider: "codex", transcript_pruned: false, transcript_bytes: 1024, transcript_lines: 12 },
                can_stop: false,
                can_diagnose: false,
                can_resume: false,
                app_stop_path: "/api/v1/app/jobs/42/runs/9/stop",
                app_diagnose_path: "/api/v1/app/jobs/42/runs/9/diagnose",
                app_resume_path: "/api/v1/app/jobs/42/resume",
                grade_log_path: null
              }
            ]
          }
        ]
      }
    ],
    actions: {
      can_start: false,
      can_poll_feedback: true,
      can_rebase: true,
      can_check_mergeability: true,
      can_retry: true,
      can_retry_from_failed_step: false,
      can_restart: true,
      can_cancel: true,
      can_approve: true,
      can_unapprove: false,
      can_reopen: false,
      can_mark_valid: false,
      can_override_dependencies: false,
      feedback_agent_options: [],
      rebase_agent_options: [],
      retry_agent_options: []
    },
    paths: {
      job_path: "/jobs/42",
      source_path: "/jobs/42/source",
      app_detail_path: "/api/v1/app/jobs/42",
      app_source_path: "/api/v1/app/jobs/42/source",
      app_timeline_path: "/api/v1/app/jobs/42/timeline",
      app_start_path: "/api/v1/app/jobs/42/start",
      app_run_again_path: "/api/v1/app/jobs/42/run_again",
      app_restart_path: "/api/v1/app/jobs/42/restart",
      app_cancel_path: "/api/v1/app/jobs/42/cancel",
      app_approve_path: "/api/v1/app/jobs/42/approve",
      app_unapprove_path: "/api/v1/app/jobs/42/unapprove",
      app_reopen_path: "/api/v1/app/jobs/42/reopen",
      app_poll_feedback_path: "/api/v1/app/jobs/42/poll_feedback",
      app_rebase_path: "/api/v1/app/jobs/42/rebase",
      app_check_mergeability_path: "/api/v1/app/jobs/42/check_mergeability",
      app_resume_path: "/api/v1/app/jobs/42/resume",
      app_tags_path: "/api/v1/app/jobs/42/tags",
      app_dependencies_path: "/api/v1/app/jobs/42/dependencies",
      app_dependency_override_path: "/api/v1/app/jobs/42/dependencies/override",
      app_stack_base_path: "/api/v1/app/jobs/42/stack_base",
      app_mark_valid_path: "/api/v1/app/jobs/42/mark_valid",
      app_attachments_path: "/api/v1/app/jobs/42/attachments",
      app_pin_path: "/api/v1/app/jobs/42/pin"
    }
  }

  return {
    ...payload,
    ...overrides,
    job: { ...payload.job, ...objectOverrides(overrides.job) },
    repository: { ...payload.repository, ...objectOverrides(overrides.repository) },
    summary: overrides.summary === undefined ? payload.summary : overrides.summary,
    landing_queue_entry: overrides.landing_queue_entry === undefined ? payload.landing_queue_entry : overrides.landing_queue_entry,
    actions: { ...payload.actions, ...objectOverrides(overrides.actions) },
    paths: { ...payload.paths, ...objectOverrides(overrides.paths) }
  }
}

function objectOverrides(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {}
}

function jobTimelinePayload() {
  return {
    job_id: 42,
    events: [
      {
        at: "2026-05-30T10:00:00Z",
        kind: "created",
        source: "workflow",
        transition_source: null,
        title: "Workflow created",
        detail: "Initial workflow queued.",
        ref: "5"
      }
    ]
  }
}

function jobSourcePayload(overrides: { withFile?: boolean } = {}) {
  return {
    job_id: 42,
    repository: { id: 3, slug: "acme/widgets", default_branch: "main", repository_path: "/repositories/3" },
    branch_name: "syrus/issue-12",
    default_ref: "main",
    selected_ref: "deadbeef12345678",
    selected_path: overrides.withFile ? "app/models/user.rb" : null,
    merge_base_sha: "aabbccdd1234567",
    branch_commits: [
      { sha: "deadbeef12345678", short_sha: "deadbee", message: "Repair aqueduct", date: "2026-05-30T11:00:00Z" }
    ],
    tree_items: [
      { path: "app/models/user.rb", name: "user.rb", size: 512, language: "ruby" },
      { path: "README.md", name: "README.md", size: 128, language: "markdown" }
    ],
    tree_truncated: false,
    file: overrides.withFile ? { path: "app/models/user.rb", name: "user.rb", size: 15, language: "ruby", content: "class User\nend\n" } : null,
    source_error: null,
    file_error: null,
    paths: {
      job_path: "/jobs/42",
      source_path: "/jobs/42/source",
      app_source_path: "/api/v1/app/jobs/42/source"
    }
  }
}

function chatPayload(overrides: {
  message?: string
  messages?: Array<Record<string, unknown>>
  turnInFlight?: boolean
  hasMoreOlder?: boolean
} = {}) {
  return {
    message: overrides.message,
    chat: {
      id: 8,
      title: "Aqueduct planning",
      chat_path: "/chats/8",
      repository: { id: 3, slug: "acme/widgets", repository_path: "/repositories/3" },
      stop_requested_at: null,
      cumulative_input_tokens: 12400,
      cumulative_output_tokens: 3200,
      cumulative_cost_usd: 0.0123
    },
    chat_available: true,
    turn_in_flight: overrides.turnInFlight ?? false,
    has_more_older: overrides.hasMoreOlder ?? false,
    messages: overrides.messages || [
      {
        type: "message",
        id: 9,
        role: "assistant",
        tool_name: null,
        content: { text: "Discuss aqueducts." },
        text: "Discuss aqueducts.",
        bookmarkable: true,
        bookmark_path: "/chats/8/bookmarks"
      }
    ],
    bookmarks: [
      { id: 1, label: "Aqueducts", chat_message_id: 9 }
    ],
    pending_actions: [],
    attachment_groups: {
      repositories: [
        { id: 2, label: "acme/widgets", detach_path: "/chats/8/attachments/2", app_detach_path: "/api/v1/app/chats/8/attachments/2" }
      ],
      epics: [],
      jobs: [],
      documents: []
    },
    documents_in_scope: [
      { id: 5, title: "Launch notes", repository_slug: "acme/widgets" }
    ],
    attachment_results: [],
    whiteboard: {
      version: 2,
      elements: [{ id: "box-1", type: "rectangle" }]
    },
    paths: {
      new_chat_path: "/chats/new",
      credentials_path: "/credentials/edit",
      repositories_path: "/repositories",
      app_messages_path: "/api/v1/app/chats/8/messages",
      app_message_path: "/api/v1/app/chats/8/message",
      app_stop_path: "/api/v1/app/chats/8/stop",
      app_refresh_path: "/api/v1/app/chats/8/refresh",
      app_reset_path: "/api/v1/app/chats/8/reset",
      app_bookmarks_path: "/api/v1/app/chats/8/bookmarks",
      app_attachments_path: "/api/v1/app/chats/8/attachments",
      app_whiteboard_path: "/api/v1/app/chats/8/whiteboard",
      chat_messages_path: "/chats/8/messages",
      chat_attachments_path: "/chats/8/attachments",
      chat_whiteboard_path: "/chats/8/whiteboard"
    }
  }
}

function chatFormPayload() {
  return {
    repositories: [
      {
        id: 3,
        slug: "acme/widgets"
      }
    ],
    repositories_path: "/repositories"
  }
}
