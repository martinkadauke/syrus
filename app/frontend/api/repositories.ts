import { getJson, patchJson, postJson } from "./client"

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

export type RepositoryFormRecord = {
  id: number | null
  owner: string
  name: string
  slug: string | null
  default_branch: string
  trigger_label: string
  polling_enabled: boolean
  prepare_enabled: boolean
  pr_cost_footer_enabled: boolean
  auto_merge_enabled: boolean
  agent_provider: string
  auto_approve_mode: string
  github_owner_id: number | null
  github_repository_id: number | null
  repository_path: string | null
}

export type RepositoryProviderOption = {
  value: string
  label: string
}

export type RepositoryAutoApproveMode = {
  value: string
  label: string
  preview: string
}

export type RepositoryFormPayload = {
  repository: RepositoryFormRecord
  configured_agent_providers: RepositoryProviderOption[]
  user_agent_provider_label: string
  auto_approve_modes: RepositoryAutoApproveMode[]
  repositories_path: string
}

export type RepositoryInput = {
  owner: string
  name: string
  default_branch: string
  trigger_label: string
  polling_enabled: boolean
  prepare_enabled: boolean
  pr_cost_footer_enabled: boolean
  auto_merge_enabled: boolean
  agent_provider: string
  auto_approve_mode: string
  github_owner_id: string
  github_repository_id: string
}

export type RepositorySavedPayload = {
  message: string
  redirect_to: string
  repository: RepositoryRow
}

export type GitHubOwnersPayload = {
  user?: string
  orgs?: string[]
  error?: string
}

export type GitHubRepositoryOption = {
  name: string
  github_repository_id: number | null
  github_owner_id: number | null
}

export type GitHubRepositoriesPayload = {
  repos?: Array<string | GitHubRepositoryOption>
  error?: string
}

export type GitHubBranchesPayload = {
  branches?: string[]
  default_branch?: string
  error?: string
}

export function fetchRepositories() {
  return getJson<RepositoriesPayload>("/api/v1/app/repositories")
}

export function fetchNewRepositoryForm() {
  return getJson<RepositoryFormPayload>("/api/v1/app/repositories/new")
}

export function fetchEditRepositoryForm(id: string) {
  return getJson<RepositoryFormPayload>(`/api/v1/app/repositories/${id}/edit`)
}

export function fetchRepositoryOwners() {
  return getJson<GitHubOwnersPayload>("/api/v1/app/repositories/owners")
}

export function fetchRepositoryOptions(owner: string, ownerType: string) {
  const params = new URLSearchParams({ owner, owner_type: ownerType })
  return getJson<GitHubRepositoriesPayload>(`/api/v1/app/repositories/repos?${params}`)
}

export function fetchRepositoryBranches(owner: string, name: string) {
  const params = new URLSearchParams({ owner, name })
  return getJson<GitHubBranchesPayload>(`/api/v1/app/repositories/branches?${params}`)
}

export function createRepository(values: RepositoryInput) {
  return postJson<RepositorySavedPayload>("/api/v1/app/repositories", { repository: values })
}

export function updateRepository(id: number, values: RepositoryInput) {
  return patchJson<RepositorySavedPayload>(`/api/v1/app/repositories/${id}`, { repository: values })
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
