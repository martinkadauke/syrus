import type { QueryClient, QueryKey } from "@tanstack/react-query"

export type AppEvent = {
  type: string
  resource: string
  id: number | string | null
  changed: string[]
  occurred_at: string
  payload?: unknown
}

export function applyAppEvent(queryClient: QueryClient, event: AppEvent) {
  for (const queryKey of queryKeysFor(event)) {
    void queryClient.invalidateQueries({ queryKey })
  }
}

export function queryKeysFor(event: AppEvent): QueryKey[] {
  switch (event.resource) {
    case "user":
      return [["bootstrap"]]
    case "job":
      return event.id == null ? [["jobs"]] : [["jobs"], ["jobs", String(event.id)]]
    case "workflow":
      return event.id == null ? [["workflows"]] : [["workflows"], ["workflows", String(event.id)]]
    case "repository":
      return event.id == null ? [["repositories"]] : [["repositories"], ["repositories", String(event.id)]]
    case "chat":
      return event.id == null ? [["chats"]] : [["chats"], ["chats", String(event.id)]]
    case "admin_overview":
      return [["admin", "overview"], ["admin", "stuck"]]
    default:
      return []
  }
}
