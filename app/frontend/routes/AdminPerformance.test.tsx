import { QueryClient, QueryClientProvider } from "@tanstack/react-query"
import { fireEvent, render, screen, waitFor, within } from "@testing-library/react"
import type { ReactNode } from "react"
import { MemoryRouter } from "react-router-dom"
import { describe, expect, it, vi } from "vitest"
import { jsonResponse } from "../testSupport"
import { AdminPerformance } from "./AdminPerformance"

describe("AdminPerformance", () => {
  it("renders performance summaries and recent events", async () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockResolvedValue(jsonResponse(performancePayload()))

    renderRoute(<AdminPerformance />)

    expect(await screen.findByRole("heading", { name: "Performance" })).toBeInTheDocument()
    expect(fetchSpy).toHaveBeenCalledWith("/api/v1/app/admin/performance?limit=200&revision_scope=current", expect.objectContaining({
      credentials: "same-origin"
    }))

    await waitFor(() => expect(screen.queryByText("Loading performance logs...")).not.toBeInTheDocument())
    const summary = await screen.findByRole("region", { name: "Performance summary" })
    expect(within(summary).getByText("yes")).toBeInTheDocument()
    expect(within(summary).getByText("2")).toBeInTheDocument()
    expect(within(summary).getByText("abcdef123456")).toBeInTheDocument()
    expect(within(summary).getByText("rails.cache")).toBeInTheDocument()
    expect(within(summary).getByText("1.00s")).toBeInTheDocument()

    expect(screen.getByText("GET /api/v1/app/chats/126")).toBeInTheDocument()
    expect(screen.getAllByText("chat_payload.recent_chats").length).toBeGreaterThan(0)
    expect(screen.getByText("SELECT `jobs`.* FROM `jobs` WHERE `jobs`.`state` = ?")).toBeInTheDocument()
    expect(screen.getByText("request")).toBeInTheDocument()
    expect(screen.getByText("246 SQL · 629ms")).toBeInTheDocument()

    fireEvent.click(screen.getByRole("button", { name: "All SHAs" }))
    await waitFor(() => expect(fetchSpy).toHaveBeenLastCalledWith("/api/v1/app/admin/performance?limit=200&revision_scope=all", expect.objectContaining({
      credentials: "same-origin"
    })))
  })
})

function renderRoute(children: ReactNode) {
  render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <MemoryRouter initialEntries={["/app-shell/admin/performance"]}>
        {children}
      </MemoryRouter>
    </QueryClientProvider>
  )
}

function performancePayload() {
  return {
    enabled: true,
    current_revision: "abcdef1234567890",
    revision_scope: "current",
    thresholds: {
      slow_request_ms: 1000,
      slow_sql_ms: 500,
      slow_phase_ms: 250,
      top_sql_fingerprint_limit: 10,
      max_sql_fingerprints_per_request: 5
    },
    storage: {
      kind: "rails.cache",
      cache_key: "syrus:performance:events",
      max_events: 200,
      expires_in_seconds: 86400
    },
    summaries: {
      slow_requests: [
        {
          method: "GET",
          path: "/api/v1/app/chats/126",
          controller: "Api::V1::App::ChatsController",
          action: "show",
          count: 2,
          total_duration_ms: 2360,
          average_duration_ms: 1180,
          max_duration_ms: 1210,
          average_sql_count: 246,
          average_sql_duration_ms: 629,
          last_seen_at: "2026-08-01T14:32:45Z"
        }
      ],
      slow_phases: [
        {
          phase: "chat_payload.recent_chats",
          count: 1,
          total_duration_ms: 620,
          average_duration_ms: 620,
          max_duration_ms: 620,
          last_seen_at: "2026-08-01T14:32:46Z",
          recent_metadata: { chat_id: 126 }
        }
      ],
      sql_fingerprints: [
        {
          fingerprint: "select_jobs_by_state",
          sample_sql: "SELECT `jobs`.* FROM `jobs` WHERE `jobs`.`state` = ?",
          name: "Job Load",
          count: 50,
          total_duration_ms: 400,
          average_duration_ms: 8,
          max_duration_ms: 30
        }
      ]
    },
    events: [
      {
        event: "syrus.performance.request",
        occurred_at: "2026-08-01T14:32:45Z",
        app_revision: "abcdef1234567890",
        duration_ms: 1180,
        method: "GET",
        path: "/api/v1/app/chats/126",
        sql_count: 246,
        sql_duration_ms: 629
      },
      {
        event: "syrus.performance.phase",
        occurred_at: "2026-08-01T14:32:46Z",
        app_revision: "abcdef1234567890",
        duration_ms: 620,
        phase: "chat_payload.recent_chats"
      }
    ]
  }
}
