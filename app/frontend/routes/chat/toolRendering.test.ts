import { describe, expect, it } from "vitest"
import { fullResultBody } from "./toolRendering"

describe("tool result rendering", () => {
  it("caps large tool result previews before the browser renders them", () => {
    const body = fullResultBody("x".repeat(25_000))

    expect(body.length).toBeLessThan(21_000)
    expect(body).toContain("Tool result preview truncated")
    expect(body).toContain("Full content remains in the chat transcript")
  })

  it("caps very tall tool result previews", () => {
    const body = fullResultBody(Array.from({ length: 500 }, (_, index) => `line ${index}`).join("\n"))

    expect(body).toContain("line 399")
    expect(body).not.toContain("line 450")
    expect(body).toContain("100 lines")
  })
})
