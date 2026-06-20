import { getJson } from "./client"

export type AdminGithubAppStatus = {
  registered: boolean
  id: number | null
  slug: string | null
  registered_at: string | null
  install_url?: string | null
}

export type AdminGithubAppRegisterPayload = {
  github_app: AdminGithubAppStatus
  github_manifest_url: string
  manifest: string
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
