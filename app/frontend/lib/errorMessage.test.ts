import { describe, expect, it } from "vitest"
import { errorMessage } from "./errorMessage"
import { ApiError } from "../api/client"

describe("errorMessage", () => {
  it("returns the ApiError's message", () => {
    expect(errorMessage(new ApiError("boom", { status: 500 }), "fallback")).toBe("boom")
  })

  it("returns the fallback for non-ApiError values", () => {
    expect(errorMessage(new Error("raw"), "fallback")).toBe("fallback")
    expect(errorMessage("a string", "fallback")).toBe("fallback")
    expect(errorMessage(null, "fallback")).toBe("fallback")
    expect(errorMessage(undefined, "fallback")).toBe("fallback")
  })
})
