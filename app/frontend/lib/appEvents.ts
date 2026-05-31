import type { QueryClient, QueryKey } from "@tanstack/react-query"
import type { ChatMessageItem, ChatPayload } from "../api/chats"

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
        messages: replaceMessageTail(current.messages, payload.replace_from_id, payload.messages),
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
  messages: ChatMessageItem[]
  turn_in_flight?: boolean
  stop_requested_at?: string | null
}

function chatReplaceTailPayload(payload: unknown): ChatReplaceTailPayload | null {
  if (!payload || typeof payload !== "object") return null

  const candidate = payload as Partial<ChatReplaceTailPayload>
  if (candidate.action !== "replace_tail") return null
  if (typeof candidate.replace_from_id !== "number") return null
  const messages = Array.isArray(candidate.messages) ? candidate.messages : Array.isArray((payload as { items?: unknown }).items) ? (payload as { items: unknown[] }).items : null
  if (!isChatMessages(messages)) return null

  return {
    action: "replace_tail",
    replace_from_id: candidate.replace_from_id,
    messages,
    turn_in_flight: typeof candidate.turn_in_flight === "boolean" ? candidate.turn_in_flight : undefined,
    stop_requested_at: typeof candidate.stop_requested_at === "string" || candidate.stop_requested_at === null ? candidate.stop_requested_at : undefined
  }
}

function isChatMessages(value: unknown): value is ChatMessageItem[] {
  return Array.isArray(value) && value.every((item) => {
    if (!item || typeof item !== "object") return false

    const candidate = item as Partial<ChatMessageItem>
    return candidate.type === "message" && typeof candidate.id === "number"
  })
}

function replaceMessageTail(current: ChatMessageItem[], replaceFromId: number, nextMessages: ChatMessageItem[]) {
  return dedupeMessages([
    ...current.filter((message) => message.id < replaceFromId),
    ...nextMessages
  ])
}

function dedupeMessages(messages: ChatMessageItem[]) {
  const seen = new Set<number>()
  const result: ChatMessageItem[] = []

  for (const message of messages) {
    if (seen.has(message.id)) continue

    seen.add(message.id)
    result.push(message)
  }

  return result
}
