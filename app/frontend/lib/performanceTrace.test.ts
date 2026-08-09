import { afterEach, describe, expect, it, vi } from "vitest"
import { recordBrowserTrace, resetBrowserPerformanceObserversForTest, startBrowserPerformanceObservers } from "./performanceTrace"
import { jsonResponse } from "../testSupport"

describe("recordBrowserTrace", () => {
  afterEach(() => {
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
    resetBrowserPerformanceObserversForTest()
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

  it("records long main-thread tasks through the global browser observer", () => {
    const callbacks: Array<PerformanceObserverCallback> = []
    const fetchSpy = vi.spyOn(window, "fetch").mockResolvedValue(jsonResponse({}))
    class FakePerformanceObserver {
      static supportedEntryTypes = [ "longtask", "event" ]

      constructor(callback: PerformanceObserverCallback) {
        callbacks.push(callback)
      }

      observe() {}
      disconnect() {}
    }
    vi.stubGlobal("PerformanceObserver", FakePerformanceObserver)

    startBrowserPerformanceObservers({ enabled: true })
    callbacks[0]?.({
      getEntries: () => [ { duration: 125.42, entryType: "longtask", name: "self", startTime: 12.34 } as PerformanceEntry ]
    } as PerformanceObserverEntryList, {} as PerformanceObserver)

    expect(fetchSpy).toHaveBeenCalledWith("/api/v1/app/performance_events", expect.objectContaining({
      body: expect.stringContaining("browser.long_task")
    }))
  })

  it("does not start browser observers when performance logging is disabled", () => {
    const observe = vi.fn()
    class FakePerformanceObserver {
      static supportedEntryTypes = [ "longtask" ]

      constructor(_callback: PerformanceObserverCallback) {}

      observe = observe
      disconnect() {}
    }
    vi.stubGlobal("PerformanceObserver", FakePerformanceObserver)

    startBrowserPerformanceObservers({ enabled: false })

    expect(observe).not.toHaveBeenCalled()
  })
})
