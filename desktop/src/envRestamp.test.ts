import { describe, expect, it } from "vitest"
import { restampEnvPort } from "../electron/installer/envRestamp"

// A TEST build that adopts an existing install's .env (to keep its data volume
// decryptable) must still bind ITS OWN port — the picked .env may belong to the
// production stack (3000). restampEnvPort forces the port for both SYRUS_PORT
// and SYRUS_APP_HOST, replacing an existing line or APPENDING one when absent.
describe("restampEnvPort", () => {
  it("rewrites an existing production port to the test port", () => {
    const input = "SYRUS_PORT=3000\nSYRUS_APP_HOST=localhost:3000\nSECRET=keep\n"
    const out = restampEnvPort(input, 3001)
    expect(out).toContain("SYRUS_PORT=3001")
    expect(out).toContain("SYRUS_APP_HOST=localhost:3001")
    // Unrelated lines are preserved untouched.
    expect(out).toContain("SECRET=keep")
    expect(out).not.toContain("3000")
  })

  it("APPENDS the port lines when the picked .env has none (the silent-fallback bug)", () => {
    // Without appending, install.sh copies the .env verbatim and docker-compose
    // falls back to ${SYRUS_PORT:-3000} — binding production's port.
    const input = "SECRET_KEY_BASE=abc\nRAILS_ENV=production\n"
    const out = restampEnvPort(input, 3001)
    expect(out).toContain("\nSYRUS_PORT=3001\n")
    expect(out).toContain("\nSYRUS_APP_HOST=localhost:3001\n")
    expect(out).toContain("SECRET_KEY_BASE=abc")
  })

  it("appends a separating newline when the file doesn't end in one", () => {
    const out = restampEnvPort("SECRET=abc", 3001)
    expect(out).toBe("SECRET=abc\nSYRUS_PORT=3001\nSYRUS_APP_HOST=localhost:3001\n")
  })

  it("handles an empty .env by writing just the two port lines", () => {
    expect(restampEnvPort("", 3001)).toBe("SYRUS_PORT=3001\nSYRUS_APP_HOST=localhost:3001\n")
  })

  it("replaces one line and appends the other when only SYRUS_PORT is present", () => {
    const out = restampEnvPort("SYRUS_PORT=9999\n", 3001)
    expect(out).toContain("SYRUS_PORT=3001")
    expect(out).toContain("SYRUS_APP_HOST=localhost:3001")
    expect(out).not.toContain("9999")
  })

  it("stamps the stable port too when asked (helper is channel-agnostic; caller gates)", () => {
    // The helper itself doesn't know the channel — installerDriver only CALLS it
    // on the test channel. Given 3000 it still produces a valid result.
    const out = restampEnvPort("SYRUS_PORT=3005\n", 3000)
    expect(out).toContain("SYRUS_PORT=3000")
  })
})
