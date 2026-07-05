import type { WebContents } from "electron"
import type { Credentials } from "./credentialsStore.js"

// Auto-provisions the menu-bar Bearer token from the signed-in webview
// session so users never paste a token by hand. The script runs inside the
// page, riding its session cookie AND its meta[name=csrf-token] — no cookie
// or CSRF plumbing in the main process. A 403 (non-admin on a remote
// instance) falls back silently to the manual paste flow in Preferences.
const PROVISION_SCRIPT = `
  (async () => {
    try {
      const status = await fetch("/api/v1/app/auth/status", { headers: { Accept: "application/json" } })
      if (!status.ok) return { state: "signed_out" }
      const statusPayload = await status.json()
      if (!statusPayload || statusPayload.authenticated !== true) return { state: "signed_out" }

      const meta = document.querySelector('meta[name="csrf-token"]')
      const csrf = meta ? meta.getAttribute("content") : null
      if (!csrf) return { state: "no_csrf" }

      const response = await fetch("/api/v1/app/desktop/api_token", {
        method: "POST",
        headers: { "X-CSRF-Token": csrf, Accept: "application/json" }
      })
      if (response.status === 403) return { state: "forbidden" }
      if (!response.ok) return { state: "error" }

      const payload = await response.json()
      return { state: "ok", apiToken: payload.api_token }
    } catch {
      return { state: "error" }
    }
  })()
`

type ProvisionResult =
  | "already-configured"
  | "different-instance"
  | "provisioned"
  | "signed_out"
  | "no_csrf"
  | "forbidden"
  | "error"

type ProvisionDeps = {
  getCachedCredentials: () => Credentials | null
  // main.ts's saveCredentials: validates against the server, writes
  // ~/.syrus/credentials, and starts the notification cable.
  saveCredentials: (credentials: Credentials) => Promise<unknown>
}

const normalizeUrl = (url: string) => url.trim().replace(/\/+$/, "")

export const maybeProvisionDesktopToken = async (
  webContents: WebContents,
  serverUrl: string,
  deps: ProvisionDeps
): Promise<ProvisionResult> => {
  const normalized = normalizeUrl(serverUrl)
  const cached = deps.getCachedCredentials()
  if (cached) {
    // ~/.syrus/credentials is shared with the syrus CLI. Credentials
    // configured for a DIFFERENT instance must never be overwritten by
    // auto-provisioning — that would silently retarget the user's CLI.
    return normalizeUrl(cached.url) === normalized ? "already-configured" : "different-instance"
  }

  let result: { state?: string; apiToken?: unknown }
  try {
    result = (await webContents.executeJavaScript(PROVISION_SCRIPT, true)) as { state?: string; apiToken?: unknown }
  } catch {
    return "error"
  }

  if (result?.state === "ok" && typeof result.apiToken === "string" && result.apiToken !== "") {
    try {
      await deps.saveCredentials({ url: normalized, token: result.apiToken })
      return "provisioned"
    } catch {
      return "error"
    }
  }

  const state = result?.state
  if (state === "signed_out" || state === "no_csrf" || state === "forbidden") {
    return state
  }

  return "error"
}
