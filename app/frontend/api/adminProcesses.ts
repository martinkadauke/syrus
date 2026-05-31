import { getJson, postJson } from "./client"
import type { AdminSmartFolderPayload } from "./adminSmartFolders"

export type ProcessStateFilter = "running" | "finished" | "all"

export type SpawnedProcessPayload = {
  id: number
  kind: string
  command: string
  workdir: string | null
  hostname: string | null
  pid: number | null
  pgid: number | null
  started_at: string | null
  last_chunk_at: string | null
  finished_at: string | null
  duration_s: number | null
  exit_status: number | null
  outcome: string | null
  wall_timeout_s: number | null
  silent_timeout_s: number | null
  run_id: number | null
  workflow_id: number | null
  stale: boolean
  kill_requested_at: string | null
  kill_requested_by_user_id: number | null
  host_metrics?: Record<string, unknown> | null
}

export type AdminProcessesPayload = AdminSmartFolderPayload & {
  processes: SpawnedProcessPayload[]
  running_total: number
}

export function fetchAdminProcesses(search = "") {
  return getJson<AdminProcessesPayload>(`/api/v1/app/admin/processes${search}`)
}

export function fetchAdminProcess(id: string) {
  return getJson<SpawnedProcessPayload>(`/api/v1/app/admin/processes/${id}`)
}

export function killAdminProcess(id: number) {
  return postJson<SpawnedProcessPayload>(`/api/v1/app/admin/processes/${id}/kill`)
}
