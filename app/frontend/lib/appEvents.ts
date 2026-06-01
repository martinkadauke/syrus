import type { QueryClient, QueryKey } from "@tanstack/react-query"
import type { ChatMessageItem, ChatPayload, ChatRecord } from "../api/chats"

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

  const replaceTail = chatReplaceTailPayload(event.payload)
  if (replaceTail) {
    queryClient.setQueriesData<ChatPayload>(
      { queryKey: ["chats", String(event.id)] },
      (current) => {
        if (!current) return current

        return {
          ...current,
          turn_in_flight: replaceTail.turn_in_flight ?? current.turn_in_flight,
          agent_busy: replaceTail.agent_busy ?? current.agent_busy,
          messages: replaceMessageTail(current.messages, replaceTail.replace_from_id, replaceTail.messages),
          chat: {
            ...current.chat,
            stop_requested_at: replaceTail.stop_requested_at ?? current.chat.stop_requested_at
          }
        }
      }
    )
    return true
  }

  const controls = chatControlsPayload(event.payload)
  if (controls) {
    queryClient.setQueriesData<ChatPayload>(
      { queryKey: ["chats", String(event.id)] },
      (current) => {
        if (!current) return current

        return {
          ...current,
          turn_in_flight: controls.turn_in_flight,
          agent_busy: controls.agent_busy ?? current.agent_busy,
          chat: {
            ...current.chat,
            stop_requested_at: controls.stop_requested_at
          }
        }
      }
    )
    return true
  }

  const header = chatHeaderPayload(event.payload)
  if (header) {
    queryClient.setQueriesData<ChatPayload>(
      { queryKey: ["chats", String(event.id)] },
      (current) => current ? { ...current, chat: { ...current.chat, ...header.chat } } : current
    )
    return true
  }

  return false
}

type ChatReplaceTailPayload = {
  action: "replace_tail"
  replace_from_id: number
  messages: ChatMessageItem[]
  turn_in_flight?: boolean
  agent_busy?: boolean
  stop_requested_at?: string | null
}

type ChatControlsPayload = {
  action: "update_controls"
  turn_in_flight: boolean
  agent_busy?: boolean
  stop_requested_at: string | null
}

type ChatHeaderPayload = {
  action: "update_header"
  chat: Partial<Pick<ChatRecord, "title" | "stop_requested_at" | "cumulative_input_tokens" | "cumulative_output_tokens" | "cumulative_cost_usd">>
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
    agent_busy: typeof candidate.agent_busy === "boolean" ? candidate.agent_busy : undefined,
    stop_requested_at: typeof candidate.stop_requested_at === "string" || candidate.stop_requested_at === null ? candidate.stop_requested_at : undefined
  }
}

function chatControlsPayload(payload: unknown): ChatControlsPayload | null {
  if (!payload || typeof payload !== "object") return null

  const candidate = payload as Partial<ChatControlsPayload>
  if (candidate.action !== "update_controls") return null
  if (typeof candidate.turn_in_flight !== "boolean") return null
  if (typeof candidate.stop_requested_at !== "string" && candidate.stop_requested_at !== null) return null

  return {
    action: "update_controls",
    turn_in_flight: candidate.turn_in_flight,
    agent_busy: typeof candidate.agent_busy === "boolean" ? candidate.agent_busy : undefined,
    stop_requested_at: candidate.stop_requested_at
  }
}

function chatHeaderPayload(payload: unknown): ChatHeaderPayload | null {
  if (!payload || typeof payload !== "object") return null

  const candidate = payload as Partial<ChatHeaderPayload>
  if (candidate.action !== "update_header") return null
  if (!candidate.chat || typeof candidate.chat !== "object") return null

  const chat = candidate.chat
  const updates: ChatHeaderPayload["chat"] = {}
  if (typeof chat.title === "string" || chat.title === null) updates.title = chat.title
  if (typeof chat.stop_requested_at === "string" || chat.stop_requested_at === null) updates.stop_requested_at = chat.stop_requested_at
  if (typeof chat.cumulative_input_tokens === "number") updates.cumulative_input_tokens = chat.cumulative_input_tokens
  if (typeof chat.cumulative_output_tokens === "number") updates.cumulative_output_tokens = chat.cumulative_output_tokens
  if (typeof chat.cumulative_cost_usd === "number") updates.cumulative_cost_usd = chat.cumulative_cost_usd

  return {
    action: "update_header",
    chat: updates
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
