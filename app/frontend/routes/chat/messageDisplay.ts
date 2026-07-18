// Message-display classification/formatting helpers extracted from Chat.tsx.
//
// Pure predicates and formatters over the render items: image-attachment data
// URLs, gathering image attachments, low-priority/proposal-outcome system
// message checks, agent-active detection, counting incoming visible messages,
// and the relative message timestamp. Read only the chat API types plus the
// shared contentRecord util and renderMessage builder.
import type { ChatMessageItem, ChatPayload, ChatRenderItem } from "../../api/chats"
import { contentRecord } from "./utils"
import { renderMessage } from "./streamBuilders"

export type ChatMessageImageAttachment = { name: string; mime_type: string; data: string }

export function attachmentDataUrl(attachment: ChatMessageImageAttachment) {
  return `data:${attachment.mime_type};base64,${attachment.data}`
}

export function imageAttachments(messages: ChatRenderItem[]) {
  return messages.flatMap((message) => {
    if (message.type !== "message") return []

    return (message.attachments || [])
      .filter((attachment): attachment is ChatMessageImageAttachment => attachment.mime_type.startsWith("image/"))
      .map((attachment, index) => ({ attachment, key: `${message.id}-${attachment.name}-${index}` }))
  })
}

export function isLowPrioritySystemMessage(item: ChatRenderItem) {
  return item.type === "message" &&
    item.role === "system" &&
    !isProposalOutcomeSystemMessage(item) &&
    ["neutral", "success"].includes(item.system?.tone || "neutral")
}

export function isProposalOutcomeSystemMessage(item: Extract<ChatRenderItem, { type: "message" }>) {
  return contentRecord(item.content)?.source === "proposal_notification"
}

export function isAgentActive(payload: ChatPayload) {
  return payload.agent_busy || payload.turn_in_flight || payload.switching_provider
}

export function countIncomingVisibleMessages(messages: ChatMessageItem[], previousMaxMessageId: number, showSystemMessages: boolean) {
  return messages.filter((message) => {
    if (message.id <= previousMaxMessageId) return false
    const item = renderMessage(message)
    if (item === null) return false

    return showSystemMessages || !isLowPrioritySystemMessage(item)
  }).length
}

export function formatMessageTimestamp(createdAt: string): string {
  const date = new Date(createdAt)
  const now = new Date()
  const diffMs = now.getTime() - date.getTime()
  const diffMinutes = Math.floor(diffMs / 60_000)
  const diffHours = Math.floor(diffMinutes / 60)

  if (diffMinutes < 1) return "just now"
  if (diffMinutes < 60) return `${diffMinutes}m ago`
  if (diffHours < 24) return `${diffHours}h ago`

  const m = date.getMonth() + 1
  const d = date.getDate()
  const hh = date.getHours()
  const mm = String(date.getMinutes()).padStart(2, "0")
  const period = hh >= 12 ? "pm" : "am"
  const h = hh % 12 || 12

  if (date.getFullYear() === now.getFullYear()) {
    return `${m}/${d} ${h}:${mm}${period}`
  }
  return `${m}/${d}/${date.getFullYear()} ${h}:${mm}${period}`
}
