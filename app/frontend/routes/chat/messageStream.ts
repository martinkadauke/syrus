// Message-stream DOM/scroll geometry helpers extracted from Chat.tsx.
//
// Pure browser-API utilities (no React/JSX) for the chat message list:
// bottom/near-top detection, "needs older messages" fill check, smooth/instant
// scroll-to-bottom, message anchor lookup, scroll-into-view, and parsing a
// message id out of a #message-N hash. They read only the shared scroll
// thresholds, so they live outside the 6k-line Chat.tsx.
import { CHAT_BOTTOM_THRESHOLD_PX, CHAT_INITIAL_FILL_MARGIN_PX, CHAT_TOP_LOAD_THRESHOLD_PX } from "./constants"

export function isMessageStreamAtBottom(element: HTMLElement) {
  return element.scrollHeight - element.scrollTop - element.clientHeight <= CHAT_BOTTOM_THRESHOLD_PX
}

export function isMessageStreamNearTop(element: HTMLElement) {
  return element.scrollTop <= CHAT_TOP_LOAD_THRESHOLD_PX
}

export function messageStreamNeedsOlderMessages(element: HTMLElement) {
  return element.clientHeight > 0 && element.scrollHeight <= element.clientHeight + CHAT_INITIAL_FILL_MARGIN_PX
}

export function scrollMessageStreamToBottom(element: HTMLElement | null, options: { smooth?: boolean } = {}) {
  if (!element) return
  // Smooth only for explicit user gestures under chat_polish; auto-follow
  // during streaming stays instant so the viewport never chases animations.
  const reduceMotion = typeof window !== "undefined" && window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches
  if (options.smooth && !reduceMotion && typeof element.scrollTo === "function") {
    element.scrollTo({ top: element.scrollHeight, behavior: "smooth" })
    return
  }
  element.scrollTop = element.scrollHeight
}

export function findChatMessageAnchor(stream: HTMLElement, messageId: number) {
  return stream.querySelector<HTMLElement>(`#message-${messageId}`)
}

export function scrollChatMessageIntoView(element: HTMLElement) {
  if (typeof element.scrollIntoView === "function") {
    element.scrollIntoView({ block: "start", behavior: "smooth" })
  }
}

export function messageIdFromHash(hash: string) {
  const match = hash.match(/^#message-(\d+)$/)
  if (!match) return null

  const messageId = Number.parseInt(match[1], 10)
  return Number.isFinite(messageId) && messageId > 0 ? messageId : null
}
