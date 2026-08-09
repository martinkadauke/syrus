import { afterEach, describe, expect, it, vi } from "vitest"
import { recordBrowserTrace } from "./performanceTrace"
import { jsonResponse } from "../testSupport"

describe("recordBrowserTrace", () => {
  afterEach(() => {
    vi.restoreAllMocks()
    document.getElementById("syrus-bootstrap-data")?.remove()
  })

  it("sends when the caller has live enabled evidence even if initial bootstrap is absent", () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockResolvedValue(jsonResponse({}))

    recordBrowserTrace({
      trace_id: "trace-1",
      name: "dashboard.route",
      path: "/dashboard/jobs",
      duration_ms: 100,
      visibility_state: "visible"
    }, { enabled: true })

    expect(fetchSpy).toHaveBeenCalledWith("/api/v1/app/performance_events", expect.objectContaining({
      method: "POST",
      credentials: "same-origin"
    }))
  })

  it("does not send when the caller has live disabled evidence", () => {
    const fetchSpy = vi.spyOn(window, "fetch").mockResolvedValue(jsonResponse({}))

    recordBrowserTrace({
      trace_id: "trace-1",
      name: "dashboard.route",
      path: "/dashboard/jobs",
      duration_ms: 100,
      visibility_state: "visible"
    }, { enabled: false })

    expect(fetchSpy).not.toHaveBeenCalled()
  })
})
