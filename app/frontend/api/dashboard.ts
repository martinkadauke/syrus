import { getJson, patchJson } from "./client"

export type DashboardSubject = "job" | "epic" | "workflow"

export type DashboardRepository = {
  id: number
  slug: string
}

export type DashboardTag = {
  id: number
  name: string
  color: string
}

export type DashboardJobItem = {
  type: "job"
  id: number
  kind: string
  title: string
  state: string
  summary_state: string
  validity: string
  priority: string
  issue_number: number | null
  branch_name: string | null
  pr_number: number | null
  latest_workflow_state: string
  created_at: string | null
  updated_at: string | null
  started_at: string | null
  finished_at: string | null
  repository: DashboardRepository
  tags: DashboardTag[]
  paths: {
    job_path: string
    source_path: string
  }
}

export type DashboardEpicItem = {
  type: "epic"
  id: number
  number: number
  display_number: string
  title: string
  state: string
  auto_approve_mode: string
  created_at: string | null
  updated_at: string | null
  done_at: string | null
  repository: DashboardRepository
  paths: {
    epic_path: string
    edit_epic_path: string
  }
}

export type DashboardWorkflowItem = {
  type: "workflow"
  id: number
  state: string
  trigger_kind: string
  agent_provider: string
  created_at: string | null
  updated_at: string | null
  started_at: string | null
  finished_at: string | null
  steps_count: number
  job: {
    id: number
    title: string
    state: string
    repository: DashboardRepository
    path: string
  }
}

export type DashboardItem = DashboardJobItem | DashboardEpicItem | DashboardWorkflowItem

export type DashboardSmartFolder = {
  id: number
  name: string
  kind: string
  subject_type: string
  active: boolean
  path: string
}

export type DashboardPayload = {
  subject: DashboardSubject
  view: string
  page: number
  per_page: number
  total: number
  total_pages: number
  counts: {
    jobs: number
    epics: number
    workflows: number
  }
  preferences: {
    sort: Record<string, string>
    visible_columns: string[]
    kanban_lanes: string[]
    raw: Record<string, unknown>
  }
  controls: {
    views: string[]
    sort_columns: string[]
    sort_directions: string[]
  }
  smart_folders: DashboardSmartFolder[]
  active_smart_folder_id: number | null
  items: DashboardItem[]
  paths: {
    dashboard_path: string
    dashboard_jobs_path: string
    dashboard_epics_path: string
    dashboard_workflows_path: string
    app_dashboard_path: string
  }
}

export type DashboardPreferencesInput = {
  subject: DashboardSubject
  sort_column?: string
  sort_direction?: string
  visible_columns?: string[]
  kanban_lanes?: string[]
}

export type DashboardPreferencesPayload = {
  message: string
  dashboard_preferences: Record<string, unknown>
}

export function fetchDashboard(search = "") {
  return getJson<DashboardPayload>(`/api/v1/app/dashboard${search}`)
}

export function updateDashboardPreferences(input: DashboardPreferencesInput) {
  return patchJson<DashboardPreferencesPayload>("/api/v1/app/dashboard/preferences", input)
}
