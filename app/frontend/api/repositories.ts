import { getJson, postJson } from "./client"

export type RepositoryRow = {
  id: number
  slug: string
  owner: string
  name: string
  default_branch: string
  trigger_label: string
  polling_enabled: boolean
  archived: boolean
  archived_at: string | null
  agent_provider: string | null
  agent_provider_label: string
  last_poll_status: string | null
  last_poll_started_at: string | null
  last_poll_error: string | null
  repository_path: string
  edit_repository_path: string
}

export type RepositoriesPayload = {
  active_repositories: RepositoryRow[]
  archived_repositories: RepositoryRow[]
  new_repository_path: string
  message?: string | null
}

export function fetchRepositories() {
  return getJson<RepositoriesPayload>("/api/v1/app/repositories")
}

export function pollRepository(id: number) {
  return postJson<RepositoriesPayload>(`/api/v1/app/repositories/${id}/poll`)
}

export function archiveRepository(id: number) {
  return postJson<RepositoriesPayload>(`/api/v1/app/repositories/${id}/archive`)
}

export function unarchiveRepository(id: number) {
  return postJson<RepositoriesPayload>(`/api/v1/app/repositories/${id}/unarchive`)
}
