import { readInitialBootstrap } from "../api/bootstrap"
import type { JsonResponseMeta } from "../api/client"

export type BrowserTraceApiRequest = {
  name: string
  path: string
  request_id: string | null
  duration_ms: number
  status: number
}

export type BrowserTracePayload = {
  trace_id: string
  name: string
  path: string
  duration_ms: number
  visibility_state: string
  metadata?: Record<string, unknown>
  api_requests?: BrowserTraceApiRequest[]
}

export function performanceLoggingEnabled(): boolean {
  return readInitialBootstrap()?.feature_flags?.performance_logging === true
}

export function browserTraceId(prefix: string): string {
  const random = typeof crypto !== "undefined" && "randomUUID" in crypto ? crypto.randomUUID() : Math.random().toString(36).slice(2)
  return `${prefix}-${Date.now().toString(36)}-${random}`
}

export function apiRequestTrace(name: string, meta: JsonResponseMeta | null | undefined): BrowserTraceApiRequest | null {
  if (!meta) return null

  return {
    name,
    path: meta.path,
    request_id: meta.requestId,
    duration_ms: Math.round(meta.durationMs * 10) / 10,
    status: meta.status
  }
}

export function recordBrowserTrace(payload: BrowserTracePayload): void {
  if (!performanceLoggingEnabled()) return

  const csrfToken = readInitialBootstrap()?.csrf_token || document.querySelector<HTMLMetaElement>("meta[name='csrf-token']")?.content
  const body = JSON.stringify({ performance_event: payload })
  void fetch("/api/v1/app/performance_events", {
    method: "POST",
    credentials: "same-origin",
    keepalive: body.length < 60_000,
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
      ...(csrfToken ? { "X-CSRF-Token": csrfToken } : {})
    },
    body
  }).catch(() => {})
}
