import { afterEach, describe, expect, it, vi } from "vitest"
import { fingerprintSyrus } from "../electron/installer/fingerprint"

// The classified branches of the connect probe: each failure mode must throw
// the actionable message the connect form shows verbatim, and a real Syrus
// answer (200 JSON with a boolean `authenticated`) must resolve.
const jsonResponse = (status: number, body: unknown) =>
  ({ ok: status >= 200 && status < 300, status, json: async () => body }) as Response

const rejectAs = (promise: Promise<unknown>) =>
  promise.then(
    () => {
      throw new Error("expected fingerprintSyrus to reject")
    },
    (error: unknown) => error as Error
  )

afterEach(() => {
  vi.unstubAllGlobals()
})

describe("fingerprintSyrus", () => {
  it("accepts a Syrus answer and probes the unauthenticated auth-status endpoint", async () => {
    const fetchMock = vi.fn().mockResolvedValue(jsonResponse(200, { authenticated: false }))
    vi.stubGlobal("fetch", fetchMock)

    await expect(fingerprintSyrus("http://localhost:3000")).resolves.toBeUndefined()
    expect(fetchMock).toHaveBeenCalledWith(
      "http://localhost:3000/api/v1/app/auth/status",
      expect.objectContaining({ signal: expect.any(AbortSignal) })
    )
  })

  it("suggests :3000 when nothing answers at a portless address", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new TypeError("fetch failed")))

    const error = await rejectAs(fingerprintSyrus("http://192.168.64.1"))
    expect(error.message).toContain("Nothing answered at http://192.168.64.1.")
    expect(error.message).toContain("local installs use :3000")
  })

  it("skips the :3000 lecture when the address already carries a port", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new TypeError("fetch failed")))

    const error = await rejectAs(fingerprintSyrus("http://192.168.64.1:8080"))
    expect(error.message).toContain("Nothing answered at http://192.168.64.1:8080.")
    expect(error.message).not.toContain(":3000")
  })

  it("points a 403 at SYRUS_ALLOWED_HOSTS — the fix is server-side", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(jsonResponse(403, {})))

    const error = await rejectAs(fingerprintSyrus("http://syrus.internal:3000"))
    expect(error.message).toContain("refused this hostname")
    expect(error.message).toContain("SYRUS_ALLOWED_HOSTS")
  })

  it("rejects a non-OK answer as not-Syrus", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(jsonResponse(500, {})))

    const error = await rejectAs(fingerprintSyrus("http://192.168.64.1:8080"))
    expect(error.message).toContain("doesn't look like a Syrus instance")
  })

  it("rejects a 200 whose payload lacks the boolean authenticated flag", async () => {
    // Every Rails 7.1+ app ships /up; a foreign app's 200 must not pass.
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(jsonResponse(200, { status: "ok" })))

    const error = await rejectAs(fingerprintSyrus("http://192.168.64.1:8080"))
    expect(error.message).toContain("doesn't look like a Syrus instance")
  })

  it("rejects a 200 whose body isn't JSON at all", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        json: async () => {
          throw new SyntaxError("Unexpected token '<'")
        }
      } as unknown as Response)
    )

    const error = await rejectAs(fingerprintSyrus("http://192.168.64.1:8080"))
    expect(error.message).toContain("doesn't look like a Syrus instance")
  })
})
