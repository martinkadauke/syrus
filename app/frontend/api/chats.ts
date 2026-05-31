import { deleteJson, getJson, postJson } from "./client"

export type ChatRepository = {
  id: number
  slug: string
  repository_path?: string
}

export type ChatRecord = {
  id: number
  title: string | null
  chat_path: string
  repository: ChatRepository | null
  stop_requested_at: string | null
  cumulative_input_tokens: number
  cumulative_output_tokens: number
  cumulative_cost_usd: number
}

export type ChatSystemMessage = {
  tone: "success" | "warning" | "error" | "neutral"
  label: string
  body: string
}

export type ChatProposal = {
  id: number
  kind: string
  kind_label: string
  state: string
  state_label: string
  title: string
  slug: string
  body: string
  proposed: boolean
  resolved: boolean
  epic_bundle: boolean
  scoped_repository_slug: string | null
  dependencies: string[]
  target_epic_label: string | null
  confirm_path: string
  reject_path: string
  app_confirm_path: string
  app_reject_path: string
  materialized_label: string | null
  materialized_path: string | null
  active_children_count?: number
  children?: ChatProposalChild[]
}

export type ChatProposalChild = {
  id: number
  title: string
  slug: string
  body: string
  state: string
  state_label: string
  proposed: boolean
  repository_slug: string | null
  dependencies: string[]
  reject_path: string
  app_reject_path: string
}

export type ChatStructuredTool = {
  name: string
  payload: unknown
  proposal_id: number | null
  proposal_state_label: string | null
}

export type ChatMessageItem = {
  type: "message"
  id: number
  role: "user" | "assistant" | "tool_use" | "tool_result" | "system"
  text: string
  bookmarkable: boolean
  bookmark_path: string
  proposal?: ChatProposal | null
  tool?: ChatStructuredTool
  system?: ChatSystemMessage
}

export type ChatToolGroupItem = {
  type: "tool_group"
  tool: string
  calls: Array<{
    message_id: number
    detail: string
    result_body: string
    result_error: boolean
  }>
}

export type ChatRenderItem = ChatMessageItem | ChatToolGroupItem

export type ChatBookmark = {
  id: number
  label: string
  chat_message_id: number
}

export type ChatPendingAction = {
  id: number
  label: string
  action: string | null
  action_type: string | null
  app_confirm_path: string
  app_cancel_path: string
}

export type ChatAttachmentRow = {
  id: number
  label: string
  detach_path: string
  app_detach_path: string
}

export type ChatDocumentScope = {
  id: number
  title: string
  repository_slug: string | null
}

export type ChatAttachmentResult = {
  type: string
  id: number
  label: string
}

export type NewChatPayload = {
  repositories: ChatRepository[]
  repositories_path: string
}

export type CreateChatInput = {
  repositoryId: string
  text: string
}

export type ChatCreatedPayload = {
  message: string
  redirect_to: string
  chat: ChatRecord
}

export type ChatPayload = {
  message?: string | null
  chat: ChatRecord
  chat_available: boolean
  turn_in_flight: boolean
  has_more_older: boolean
  messages: ChatRenderItem[]
  bookmarks: ChatBookmark[]
  pending_actions: ChatPendingAction[]
  attachment_groups: {
    repositories: ChatAttachmentRow[]
    epics: ChatAttachmentRow[]
    jobs: ChatAttachmentRow[]
    documents: ChatAttachmentRow[]
  }
  documents_in_scope: ChatDocumentScope[]
  attachment_results: ChatAttachmentResult[]
  whiteboard: {
    version: number
    elements: unknown[]
  }
  paths: {
    new_chat_path: string
    credentials_path: string
    repositories_path: string
    app_messages_path: string
    app_message_path: string
    app_stop_path: string
    app_refresh_path: string
    app_reset_path: string
    app_bookmarks_path: string
    app_attachments_path: string
    chat_messages_path: string
    chat_attachments_path: string
    chat_whiteboard_path: string
  }
}

export type ChatMessagesPayload = {
  has_more_older: boolean
  messages: ChatRenderItem[]
}

export function fetchChat(id: string, search = "") {
  return getJson<ChatPayload>(`/api/v1/app/chats/${id}${search}`)
}

export function fetchChatMessages(path: string, before: number) {
  return getJson<ChatMessagesPayload>(`${path}?before=${encodeURIComponent(String(before))}`)
}

export function fetchNewChat() {
  return getJson<NewChatPayload>("/api/v1/app/chats/new")
}

export function createChat(values: CreateChatInput) {
  return postJson<ChatCreatedPayload>("/api/v1/app/chats", {
    repository_id: values.repositoryId,
    chat_message: { text: values.text }
  })
}

export function sendChatMessage(path: string, text: string) {
  return postJson<ChatPayload>(path, { chat_message: { text } })
}

export function stopChat(path: string) {
  return postJson<ChatPayload>(path)
}

export function refreshChat(path: string) {
  return postJson<ChatPayload>(path)
}

export function resetChat(path: string) {
  return postJson<ChatPayload>(path)
}

export function createChatBookmark(path: string, messageId: number, label: string) {
  return postJson<ChatPayload>(path, {
    message_id: messageId,
    chat_bookmark: { label }
  })
}

export function addChatAttachment(path: string, record: ChatAttachmentResult) {
  return postJson<ChatPayload>(path, {
    attachable_type: record.type,
    attachable_id: record.id
  })
}

export function deleteChatAttachment(path: string) {
  return deleteJson<ChatPayload>(path)
}

export function confirmChatProposal(path: string) {
  return postJson<ChatPayload>(path)
}

export function rejectChatProposal(path: string) {
  return postJson<ChatPayload>(path)
}

export function confirmPendingAction(path: string) {
  return postJson<ChatPayload>(path)
}

export function cancelPendingAction(path: string) {
  return deleteJson<ChatPayload>(path)
}
