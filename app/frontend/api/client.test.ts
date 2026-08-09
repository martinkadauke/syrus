import { afterEach, describe, expect, it, vi } from "vitest"
import { jsonResponse } from "../testSupport"

const reloadPageMock = vi.hoisted(() => vi.fn())

vi.mock("../lib/pageReload", () => ({
  reloadPage: reloadPageMock
}))

describe("API revision reload guard", () => {
  afterEach(() => {
    vi.restoreAllMocks()
    reloadPageMock.mockClear()
    window.sessionStorage.clear()
    document.getElementById("syrus-bootstrap-data")?.remove()
    vi.resetModules()
  })

  it("does not reload when the backend revision matches the embedded frontend revision", async () => {
    const { getJson } = await import("./client")
    installBootstrapRevision("abc123")
    vi.spyOn(window, "fetch").mockResolvedValue(jsonResponseWithRevision({ ok: true }, "abc123"))

    await expect(getJson("/api/v1/app/bootstrap")).resolves.toEqual({ ok: true })

    expect(reloadPageMock).not.toHaveBeenCalled()
  })

  it("reloads once when an API response comes from a newer backend revision", async () => {
    const { getJson } = await import("./client")
    installBootstrapRevision("old123")
    vi.spyOn(window, "fetch").mockImplementation(() => Promise.resolve(jsonResponseWithRevision({ ok: true }, "new456")))

    await expect(getJson("/api/v1/app/bootstrap")).resolves.toEqual({ ok: true })
    await expect(getJson("/api/v1/app/dashboard")).resolves.toEqual({ ok: true })

    expect(reloadPageMock).toHaveBeenCalledTimes(1)
  })
})

function installBootstrapRevision(revision: string) {
  const script = document.createElement("script")
  script.id = "syrus-bootstrap-data"
  script.type = "application/json"
  script.textContent = JSON.stringify({ app: { revision } })
  document.body.appendChild(script)
}

function jsonResponseWithRevision(body: unknown, revision: string) {
  const response = jsonResponse(body)
  response.headers.set("X-Syrus-Revision", revision)
  return response
}
