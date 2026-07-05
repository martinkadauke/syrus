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

  // The WHATWG parser drops a scheme-default port (host:80 parses with
  // port === ""), so "did the user type a port?" must come from the raw
  // input — an explicit :80 is a choice, not a missing port.
  const typedPort = /:\d+$/.test(input)

  // Bare host or IP with no port at all: Syrus's local installs listen on
  // :3000, so assume it rather than silently probing :80.
  if (!hasScheme && !typedPort && url.port === "") {
    url.port = String(DEFAULT_SYRUS_PORT)
    return {
      state: "assumed",
      normalized: url.origin,
      hint: `Will connect to ${url.origin} — Syrus usually listens on port 3000.`
    }
  }

  // Explicit http:// with no port: honored as typed (port 80), but flagged
  // as a caveat — "assumed" renders in the neutral note tone, not the green
  // looks-good check, because this is the classic forgot-the-port case.
  if (hasScheme && url.protocol === "http:" && !typedPort && url.port === "") {
    return {
      state: "assumed",
      normalized: url.origin,
      hint: `Will connect to ${url.origin} — if nothing answers, the port may be missing (usually :3000).`
    }
  }

  return { state: "ready", normalized: url.origin, hint: `Will connect to ${url.origin}.` }
}
