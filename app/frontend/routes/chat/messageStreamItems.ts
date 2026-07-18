// Message-stream list helpers extracted from Chat.tsx.
//
// Pure operations over the render-stream item list: dedupe/merge message
// groups by id, compute a stable React key per stream item, build a cheap
// change signature for memoization, and find the oldest/newest message id.
import type { ChatMessageItem } from "../../api/chats"
import type { ChatStreamItem } from "./streamTypes"

export function mergeChatMessages(...groups: ChatMessageItem[][]) {
  const seen = new Set<string>()
  const messages: ChatMessageItem[] = []

  for (const item of groups.flat()) {
    const key = String(item.id)
    if (seen.has(key)) continue

    seen.add(key)
    messages.push(item)
  }

  return messages
}

export function renderItemKey(item: ChatStreamItem) {
  if (item.type === "timestamp") return `timestamp-${item.fullDatetime}`
  if (item.type === "day_divider") return `day-divider-${item.date}`
  if (item.type === "pending_action") return `pending-action-${item.pendingAction.id}`
  if (item.type === "message") return `message-${item.id}`

  return `tool-${item.calls.map((call) => call.message_id).join("-")}`
}

export function chatStreamItemsSignature(items: ChatStreamItem[]) {
  return items.map((item) => {
    if (item.type === "timestamp") return `${renderItemKey(item)}:${item.time}`
    if (item.type === "day_divider") return `${renderItemKey(item)}:${item.label}`
    if (item.type === "pending_action") return `${renderItemKey(item)}:${item.pendingAction.state}:${item.pendingAction.label.length}:${item.pendingAction.detail?.length || 0}`
    if (item.type === "message") return `${renderItemKey(item)}:${item.text.length}`

    return `${renderItemKey(item)}:${item.calls.map((call) => `${call.message_id}:${call.result_body.length}`).join(",")}`
  }).join("|")
}

export function oldestMessageId(messages: ChatMessageItem[]) {
  const ids = messages.map((message) => message.id)
  return ids.length > 0 ? Math.min(...ids) : null
}

export function maxMessageId(messages: ChatMessageItem[]) {
  const ids = messages.map((message) => message.id)
  return ids.length > 0 ? Math.max(...ids) : null
}
