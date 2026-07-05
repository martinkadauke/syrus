// How "Connect to your Syrus" understands what the user typed: bare IPs and
// hostnames are fine (we assume http:// and Syrus's default port 3000),
// full URLs pass through, and everything else gets a specific, human hint.
// Guidance-only — the hint never blocks submission; the driver re-normalizes
// authoritatively before probing.
//
// TWO BYTE-IDENTICAL COPIES of this file exist — desktop/src/onboarding/
// instanceUrl.ts (renderer live preview) and desktop/electron/installer/
// instanceUrl.ts (driver) — because the renderer and main-process builds
// cannot share a module (tsconfig rootDir boundaries). Edit both or
// spec/desktop/connect_flow_spec.rb fails.

export const DEFAULT_SYRUS_PORT = 3000

export type InstanceUrlAnalysis = {
  // empty: show nothing · invalid: amber guidance · assumed: we filled in
  // scheme/port, show the resulting address · ready: parses as given
  state: "empty" | "invalid" | "assumed" | "ready"
  normalized: string | null
  hint: string
}

export function analyzeInstanceUrl(raw: string): InstanceUrlAnalysis {
  const input = raw.trim()
  if (input === "") {
    return { state: "empty", normalized: null, hint: "" }
  }

  if (/\s/.test(input)) {
    return { state: "invalid", normalized: null, hint: "Server addresses can't contain spaces." }
  }

  const hasScheme = /^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(input)
  if (hasScheme && !/^https?:\/\//i.test(input)) {
    return { state: "invalid", normalized: null, hint: "Use http:// or https://." }
  }

  let url: URL
  try {
    url = new URL(hasScheme ? input : `http://${input}`)
  } catch {
    return { state: "invalid", normalized: null, hint: "Doesn't look like a server address yet." }
  }

  if (url.hostname === "") {
    return { state: "invalid", normalized: null, hint: "Doesn't look like a server address yet." }
  }

  if (url.username !== "" || url.password !== "") {
    return { state: "invalid", normalized: null, hint: "Leave usernames and passwords out of the address." }
  }

  if (url.pathname !== "/" || url.search !== "" || url.hash !== "") {
    return { state: "invalid", normalized: null, hint: "Enter just the server address — no path after the host." }
  }

  // Bare host or IP with no port: Syrus's local installs listen on :3000,
  // so assume it rather than silently probing :80.
  if (!hasScheme && url.port === "") {
    url.port = String(DEFAULT_SYRUS_PORT)
    return {
      state: "assumed",
      normalized: url.origin,
      hint: `Will connect to ${url.origin} — Syrus usually listens on port 3000.`
    }
  }

  if (hasScheme && url.protocol === "http:" && url.port === "") {
    return {
      state: "ready",
      normalized: url.origin,
      hint: `Will connect to ${url.origin} — if nothing answers, the port may be missing (usually :3000).`
    }
  }

  return { state: "ready", normalized: url.origin, hint: `Will connect to ${url.origin}.` }
}
