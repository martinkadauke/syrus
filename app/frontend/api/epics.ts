import { getJson, patchJson, postJson } from "./client"

export type EpicRepositoryOption = {
  id: number
  slug: string
}

export type EpicFormRecord = {
  id: number | null
  title: string
  description: string
  repository_id: number | null
  github_issue_url: string
  epic_path: string | null
}

export type EpicFormPayload = {
  epic: EpicFormRecord
  repositories: EpicRepositoryOption[]
  dashboard_epics_path: string
}

export type EpicInput = {
  title: string
  description: string
  repository_id: string
  github_issue_url: string
}

export type EpicSavedPayload = {
  message: string
  redirect_to: string
  epic: EpicFormRecord
}

export function fetchNewEpicForm() {
  return getJson<EpicFormPayload>("/api/v1/app/epics/new")
}

export function fetchEditEpicForm(id: string) {
  return getJson<EpicFormPayload>(`/api/v1/app/epics/${id}/edit`)
}

export function createEpic(values: EpicInput) {
  return postJson<EpicSavedPayload>("/api/v1/app/epics", { epic: values })
}

export function updateEpic(id: number, values: EpicInput) {
  return patchJson<EpicSavedPayload>(`/api/v1/app/epics/${id}`, { epic: values })
}
