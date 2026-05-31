import { fireEvent, render, screen, waitFor } from "@testing-library/react"
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
})

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
