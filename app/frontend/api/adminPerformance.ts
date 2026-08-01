import { getJson } from "./client"

export type PerformanceThresholds = {
  slow_request_ms: number
  slow_sql_ms: number
  slow_phase_ms: number
  top_sql_fingerprint_limit: number
  max_sql_fingerprints_per_request: number
}

export type PerformanceStorage = {
  kind: string
  cache_key: string
  max_events: number
  expires_in_seconds: number
}

export type SlowRequestSummary = {
  method: string | null
  path: string | null
  controller: string | null
  action: string | null
  count: number
  total_duration_ms: number
  average_duration_ms: number | null
  max_duration_ms: number | null
  average_sql_count: number | null
  average_sql_duration_ms: number | null
  last_seen_at: string | null
}

export type SlowPhaseSummary = {
  phase: string
  count: number
  total_duration_ms: number
  average_duration_ms: number | null
  max_duration_ms: number | null
  last_seen_at: string | null
  recent_metadata?: Record<string, unknown> | null
}

export type SqlFingerprintSummary = {
  fingerprint: string
  sample_sql?: string | null
  name?: string | null
  count: number
  total_duration_ms: number
  average_duration_ms: number | null
  max_duration_ms: number | null
}

export type PerformanceEvent = {
  event: string
  occurred_at?: string | null
  app_revision?: string | null
  duration_ms?: number | null
  method?: string | null
  path?: string | null
  controller?: string | null
  action?: string | null
  phase?: string | null
  name?: string | null
  sql?: string | null
  fingerprint?: string | null
  sql_count?: number | null
  sql_duration_ms?: number | null
  slow_sql_count?: number | null
  status?: number | null
  metadata?: Record<string, unknown> | null
}

export type AdminPerformancePayload = {
  enabled: boolean
  current_revision: string
  revision_scope: "current" | "all"
  thresholds: PerformanceThresholds
  storage: PerformanceStorage
  summaries: {
    slow_requests: SlowRequestSummary[]
    slow_phases: SlowPhaseSummary[]
    sql_fingerprints: SqlFingerprintSummary[]
  }
  events: PerformanceEvent[]
}

export function fetchAdminPerformance(limit = 200, revisionScope: "current" | "all" = "current") {
  const params = new URLSearchParams({ limit: String(limit), revision_scope: revisionScope })
  return getJson<AdminPerformancePayload>(`/api/v1/app/admin/performance?${params.toString()}`)
}
