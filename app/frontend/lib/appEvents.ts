import type { QueryClient, QueryKey } from "@tanstack/react-query"
import type { ChatPayload, ChatRenderItem, ChatToolGroupItem } from "../api/chats"

export type AppEvent = {
  type: string
  resource: string
  id: number | string | null
  changed: string[]
  occurred_at: string
  payload?: unknown
}

export function applyAppEvent(queryClient: QueryClient, event: AppEvent) {
  if (applyChatPayloadEvent(queryClient, event)) return

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

function applyChatPayloadEvent(queryClient: QueryClient, event: AppEvent) {
  if (event.resource !== "chat" || event.id == null) return false

  const payload = chatReplaceTailPayload(event.payload)
  if (!payload) return false

  queryClient.setQueriesData<ChatPayload>(
    { queryKey: ["chats", String(event.id)] },
    (current) => {
      if (!current) return current

      return {
        ...current,
        turn_in_flight: payload.turn_in_flight ?? current.turn_in_flight,
        messages: replaceMessageTail(current.messages, payload.replace_from_id, payload.items),
        chat: {
          ...current.chat,
          stop_requested_at: payload.stop_requested_at ?? current.chat.stop_requested_at
        }
      }
    }
  )
  return true
}

type ChatReplaceTailPayload = {
  action: "replace_tail"
  replace_from_id: number
  items: ChatRenderItem[]
  turn_in_flight?: boolean
  stop_requested_at?: string | null
}

function chatReplaceTailPayload(payload: unknown): ChatReplaceTailPayload | null {
  if (!payload || typeof payload !== "object") return null

  const candidate = payload as Partial<ChatReplaceTailPayload>
  if (candidate.action !== "replace_tail") return null
  if (typeof candidate.replace_from_id !== "number") return null
  if (!Array.isArray(candidate.items)) return null

  return {
    action: "replace_tail",
    replace_from_id: candidate.replace_from_id,
    items: candidate.items,
    turn_in_flight: typeof candidate.turn_in_flight === "boolean" ? candidate.turn_in_flight : undefined,
    stop_requested_at: typeof candidate.stop_requested_at === "string" || candidate.stop_requested_at === null ? candidate.stop_requested_at : undefined
  }
}

function replaceMessageTail(current: ChatRenderItem[], replaceFromId: number, nextItems: ChatRenderItem[]) {
  const retained = current
    .map((item) => trimItemBefore(item, replaceFromId))
    .filter((item): item is ChatRenderItem => item != null)

  return coalesceToolGroups([...retained, ...nextItems])
}

function trimItemBefore(item: ChatRenderItem, replaceFromId: number): ChatRenderItem | null {
  if (item.type === "message") return item.id < replaceFromId ? item : null

  const calls = item.calls.filter((call) => call.message_id < replaceFromId)
  return calls.length > 0 ? { ...item, calls } : null
}

function coalesceToolGroups(items: ChatRenderItem[]) {
  const coalesced: ChatRenderItem[] = []

  for (const item of items) {
    const previous = coalesced.at(-1)
    if (isToolGroup(previous) && isToolGroup(item) && previous.tool === item.tool) {
      previous.calls = dedupeToolCalls([...previous.calls, ...item.calls])
    } else {
      coalesced.push(cloneRenderItem(item))
    }
  }

  return coalesced
}

function isToolGroup(item: ChatRenderItem | undefined): item is ChatToolGroupItem {
  return item?.type === "tool_group"
}

function dedupeToolCalls(calls: ChatToolGroupItem["calls"]) {
  const seen = new Set<number>()
  const result: ChatToolGroupItem["calls"] = []

  for (const call of calls) {
    if (seen.has(call.message_id)) continue

    seen.add(call.message_id)
    result.push(call)
  }

  return result
}

function cloneRenderItem(item: ChatRenderItem): ChatRenderItem {
  return item.type === "tool_group" ? { ...item, calls: [...item.calls] } : item
}
