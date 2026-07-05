import { getJson, postJson } from "./client"

export type AdminGithubAppInstallation = {
  account_login: string
  account_type: string | null
}

export type AdminGithubAppStatus = {
  registered: boolean
  id: number | null
  slug: string | null
  registered_at: string | null
  install_url?: string | null
  installations?: AdminGithubAppInstallation[]
}

export type AdminGithubAppRegisterPayload = {
  github_app: AdminGithubAppStatus
  // Same-origin page that re-submits the manifest POST to GitHub. Opened as
  // a plain new tab; the desktop shell routes it to the default browser via
  // its syrus_external marker.
  bounce_url: string
  submit_label: string
}

export type AdminGithubAppConfirmPayload = {
  github_app: AdminGithubAppStatus
}

export function fetchAdminGithubAppRegister(origin?: string) {
  const query = origin ? `?origin=${encodeURIComponent(origin)}` : ""
  return getJson<AdminGithubAppRegisterPayload>(`/api/v1/app/admin/github_app/register${query}`)
}

export function fetchAdminGithubAppConfirm() {
  return getJson<AdminGithubAppConfirmPayload>("/api/v1/app/admin/github_app/confirm")
}

// Syrus has no webhooks, so a fresh App installation is normally only
// discovered by the recurring 5-minute sync. Fire this while a setup UI is
// waiting on GitHub — the server throttles enqueues, so polling it is cheap.
export function syncAdminGithubAppInstallations() {
  return postJson<{ enqueued: boolean }>("/api/v1/app/admin/github_app/sync_installations")
}
