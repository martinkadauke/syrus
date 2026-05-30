import { QueryClient } from "@tanstack/react-query"
import { describe, expect, it, vi } from "vitest"
import { applyAppEvent, queryKeysFor } from "./appEvents"

describe("queryKeysFor", () => {
  it("maps resource events to the query keys they invalidate", () => {
    expect(queryKeysFor(event("user", null))).toEqual([["bootstrap"]])
    expect(queryKeysFor(event("job", 42))).toEqual([["jobs"], ["jobs", "42"]])
    expect(queryKeysFor(event("workflow", 7))).toEqual([["workflows"], ["workflows", "7"]])
    expect(queryKeysFor(event("repository", 3))).toEqual([["repositories"], ["repositories", "3"]])
    expect(queryKeysFor(event("admin_overview", null))).toEqual([["admin", "overview"]])
    expect(queryKeysFor(event("unknown", 1))).toEqual([])
  })
})

describe("applyAppEvent", () => {
  it("invalidates every mapped query key", () => {
    const queryClient = new QueryClient()
    const invalidate = vi.spyOn(queryClient, "invalidateQueries")

    applyAppEvent(queryClient, event("job", 42))

    expect(invalidate).toHaveBeenCalledWith({ queryKey: ["jobs"] })
    expect(invalidate).toHaveBeenCalledWith({ queryKey: ["jobs", "42"] })
  })
})

function event(resource: string, id: number | null) {
  return {
    type: `${resource}.updated`,
    resource,
    id,
    changed: [],
    occurred_at: "2026-05-30T12:00:00.000Z"
  }
}
