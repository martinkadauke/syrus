// Shared test-support helpers. jsonResponse builds a JSON `Response` for
// stubbing fetch in Vitest specs; it had drifted into ~26 near-identical
// per-file copies, so it lives here as the single source of truth.
export function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } })
}
