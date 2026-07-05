// How "Connect to your Syrus" understands what the user typed: bare IPs and
// hostnames are fine (we assume http:// and Syrus's default port 3000 for
// the connectivity probe), full URLs pass through, and everything else gets
// a specific, human hint. Shape analysis only — the green "found it" check
// comes from actually probing the instance (ConnectRemote + the driver's
// probeInstance), never from the string looking plausible.
//
// TWO BYTE-IDENTICAL COPIES of this file exist — desktop/src/onboarding/
// instanceUrl.ts (renderer live preview) and desktop/electron/installer/
// instanceUrl.ts (driver) — because the renderer and main-process builds
// cannot share a module (tsconfig rootDir boundaries). Edit both or
// spec/desktop/connect_flow_spec.rb fails.

export const DEFAULT_SYRUS_PORT = 3000

export type InstanceUrlAnalysis = {
  // empty: show nothing · invalid: amber guidance · assumed: we filled in
  // scheme/port for the probe · ready: parses as given
  state: "empty" | "invalid" | "assumed" | "ready"
  normalized: string | null
  hint: string
}

const INCOMPLETE_HINT = "Doesn't look like a server address yet."

// The WHATWG parser "helpfully" normalizes partial or shorthand numeric
// hosts (new URL("http://192.168.") yields host 192.0.0.168), so a
// mid-typing IP would otherwise preview a confidently wrong address. A
// host made only of digits and dots must be a complete dotted-quad IPv4
// before we treat the input as parseable.
const looksLikePartialIpv4 = (host: string): boolean => {
  if (!/^[\d.]+$/.test(host)) {
    return false
  }

  const octets = host.split(".")
  if (octets.length !== 4) {
    return true
  }

  return !octets.every((octet) => /^\d{1,3}$/.test(octet) && Number(octet) <= 255)
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

  // Check the numeric-host completeness against what the user actually
  // typed, before URL normalization can rewrite it.
  const typedHost = input
    .replace(/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//, "")
    .replace(/[/:?#].*$/, "")
  if (looksLikePartialIpv4(typedHost)) {
    return { state: "invalid", normalized: null, hint: INCOMPLETE_HINT }
  }

  let url: URL
  try {
    url = new URL(hasScheme ? input : `http://${input}`)
  } catch {
    return { state: "invalid", normalized: null, hint: INCOMPLETE_HINT }
  }

  if (url.hostname === "") {
    return { state: "invalid", normalized: null, hint: INCOMPLETE_HINT }
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

  // Bare host or IP with no port at all: probe Syrus's default :3000
  // rather than silently probing :80. The preview shows exactly what will
  // be tried; port guidance beyond that lives in probe-failure messages,
  // not here (production instances are https with no port at all).
  if (!hasScheme && !typedPort && url.port === "") {
    url.port = String(DEFAULT_SYRUS_PORT)
    return { state: "assumed", normalized: url.origin, hint: `Will connect to ${url.origin}.` }
  }

  // Explicit http:// with no port: honored as typed (port 80). "assumed"
  // keeps the neutral note tone — this is the classic forgot-the-port
  // case, and the probe failure will say so if nothing answers.
  if (hasScheme && url.protocol === "http:" && !typedPort && url.port === "") {
    return { state: "assumed", normalized: url.origin, hint: `Will connect to ${url.origin}.` }
  }

  return { state: "ready", normalized: url.origin, hint: `Will connect to ${url.origin}.` }
}
