import { getJson } from "./client"

export type StuckItem = {
  kind: string
  severity: "warn" | "alarm" | string
  detail: string
  age_label: string
  run_id: number | null
  workflow_id: number | null
  workflow_slug: string | null
  workflow_path: string | null
  workflow_trigger_kind: string | null
  step_kind: string | null
  job_id: number | null
  job_path: string | null
  has_transcript: boolean
}

export type AdminStuckPayload = {
  items: StuckItem[]
}

export function fetchAdminStuck() {
  return getJson<AdminStuckPayload>("/api/v1/app/admin/stuck")
}
