import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"
import type { CSSProperties, ErrorInfo, FormEvent, KeyboardEvent, MouseEvent as ReactMouseEvent, ReactNode, UIEvent } from "react"
import { Component, useCallback, useEffect, useId, useLayoutEffect, useMemo, useRef, useState } from "react"
import { Link, useLocation, useNavigate, useParams } from "react-router-dom"
import "@excalidraw/excalidraw/index.css"
import type { ExcalidrawImperativeAPI } from "@excalidraw/excalidraw/types"
import { ApiError } from "../api/client"
import { NoticeToast } from "../components/NoticeToast"
import { formatClock } from "../components/WalkthroughRecorder"
import { refreshRecentChats, updateRecentChatCache } from "../lib/chatCache"
import { answerAgentQuestion, createWhiteboardSnapshot, fetchChat, fetchChatMessages, fetchSharedChat, fetchChatWhiteboard, fetchWhiteboardSnapshot, fetchWhiteboardSnapshots, markChatRead, patchChatWhiteboard, updateChatProvider, cancelCodingCheckout, fetchCodingFileTree, fetchCodingFileContent, fetchCodingDiff, updateChatMode, type ChatMode, type ChatAgentQuestion, type ChatBookmark, type ChatMessageItem, type ChatPayload, type ChatRenderItem, type ChatWhiteboardElement, type ChatWhiteboardScene, type SharedChatPayload, type WhiteboardSnapshot } from "../api/chats"
import { fetchBootstrap, readInitialBootstrap } from "../api/bootstrap"
import { CloseIcon } from "../components/CloseIcon"
import { GearIcon } from "../components/GearIcon"
import { createConsumer, type Subscription } from "@rails/actioncable"
import { useT } from "../hooks/useT"
import { ChatJobStatusPanel } from "./ChatJobStatusPanel"
import { errorMessage } from "../lib/errorMessage"
import { asExcalidrawElements, asExcalidrawFiles, cleanWhiteboardAppState, cleanWhiteboardFiles, cloneWhiteboardScene, signatureForScene, whiteboardScene, withFreshElementIds } from "./chat/whiteboardScene"
import { type ChatQueryKey, CHAT_WORKSPACE_COLLAPSED_KEY, CHAT_WORKSPACE_MIN_WIDTH, CHAT_WORKSPACE_TAB_KEY, CHAT_WORKSPACE_WIDTH_KEY, WHITEBOARD_MAX_ELEMENTS, WHITEBOARD_SAVE_DEBOUNCE_MS } from "./chat/constants"
import { findChatMessageAnchor, isMessageStreamAtBottom, isMessageStreamNearTop, messageIdFromHash, messageStreamNeedsOlderMessages, scrollChatMessageIntoView, scrollMessageStreamToBottom } from "./chat/messageStream"
import { appendSearch, visualViewportHeight, chatDisplayTitle, codingFilesTabVisible, formatRelativeTime, jobsTabVisible, snapshotKindLabel, diffLineClass, primaryButton, secondaryButton, errorAsError, formatCurrency, formatTokenCount, providerLabel, truncateSnapshotName, withRoutePrefix } from "./chat/utils"
import { PendingActionCard } from "./chat/ProposalCards"
import { ChatMessage, ImageLightbox, shouldAnimateMessageEntrance, ToolGroup } from "./chat/MessageCards"
import { Attachments } from "./chat/Attachments"
import { Compose } from "./chat/Compose"
import type { ChatSystemCommandHandlers } from "./chat/composeTypes"
import { chatStreamItemsSignature, maxMessageId, mergeChatMessages, oldestMessageId, renderItemKey } from "./chat/messageStreamItems"
import { buildMessageStreamItems, injectTemporalMarkers, pendingActionCardData, renderChatMessages } from "./chat/streamBuilders"
import type { MobileChatTab, WorkspaceTab } from "./chat/workspaceTabs"
import type { ChatMessageImageAttachment } from "./chat/messageDisplay"
import type { FileTreeNode } from "./chat/fileTree"
import { buildFileTree } from "./chat/fileTree"
import { attachmentDataUrl, countIncomingVisibleMessages, imageAttachments, isAgentActive, isLowPrioritySystemMessage } from "./chat/messageDisplay"
import { clampWorkspaceWidth, defaultWorkspaceTab, mobileChatTabLabel, storeWorkspacePreference, storedWorkspaceCollapsed, storedWorkspaceTab, storedWorkspaceWidth, workspaceTabClass, workspaceTabLabel } from "./chat/workspaceTabs"



type ExcalidrawComponent = typeof import("@excalidraw/excalidraw")["Excalidraw"]
type ExcalidrawApi = Pick<ExcalidrawImperativeAPI, "addFiles" | "updateScene">
export function ChatRoute() {
  const params = useParams()
  const location = useLocation()
  const id = params.id || ""
  const queryClient = useQueryClient()
  const queryKey = chatQueryKey(id, location.search)
  const prefix = routePrefix(location.pathname)
  const viewportStyle = useChatVisualViewportStyle()
  const { t } = useT("chat")
  const chat = useQuery({
    queryKey,
    queryFn: () => fetchChat(id, location.search),
    enabled: id.length > 0,
    placeholderData: (previousData, previousQuery) => (
      previousQuery?.queryKey[0] === "chats" && previousQuery.queryKey[1] === id ? previousData : undefined
    )
  })

  useEffect(() => {
    if (!id) return

    void markChatRead(id).then(() => {
      refreshRecentChats(queryClient)
    }).catch(() => undefined)
  }, [id, queryClient])

  return (
    <main
      aria-label={t("aria_chat")}
      className="mx-auto flex h-full max-w-[96rem] flex-col gap-6 overflow-hidden p-3 sm:p-6"
      style={viewportStyle}
    >
      {chat.isPending ? <PanelMessage>{t("loading_chat")}</PanelMessage> : null}
      {chat.isError ? <PanelMessage tone="error">{errorMessage(chat.error, t("error_load_chat"))}</PanelMessage> : null}
      {chat.isSuccess ? <ChatView chatId={id} payload={chat.data} prefix={prefix} queryKey={queryKey} /> : null}
    </main>
  )
}

export function SharedChatRoute() {
  const params = useParams()
  const token = params.token || ""
  const { t } = useT("chat")
  const chat = useQuery({
    queryKey: ["shared-chat", token],
    queryFn: () => fetchSharedChat(token),
    enabled: token.length > 0
  })

  return (
    <main
      aria-label={t("shared_chat_fallback_title")}
      className="mx-auto flex h-full max-w-[64rem] flex-col gap-4 overflow-hidden p-3 sm:p-6"
      style={useChatVisualViewportStyle()}
    >
      {chat.isPending ? <PanelMessage>{t("loading_shared_chat")}</PanelMessage> : null}
      {chat.isError ? <PanelMessage tone="error">{errorMessage(chat.error, t("error_load_shared_chat"))}</PanelMessage> : null}
      {chat.isSuccess ? <SharedChatView payload={chat.data} /> : null}
    </main>
  )
}

function SharedChatView({ payload }: { payload: SharedChatPayload }) {
  const { t } = useT("chat")
  return (
    <div className="flex min-h-0 flex-1 flex-col gap-4">
      <header className="flex flex-wrap items-center justify-between gap-3 border-b border-gray-200 pb-3 dark:border-gray-700">
        <h1 className="break-words text-2xl font-semibold text-gray-900 dark:text-gray-100">{payload.chat.title || t("shared_chat_fallback_title")}</h1>
        <span className="rounded border border-blue-200 bg-blue-50 px-3 py-1 text-sm font-medium text-blue-800 dark:border-blue-800 dark:bg-blue-950 dark:text-blue-200">{t("view_only")}</span>
      </header>
      <section className="min-h-0 flex-1 overflow-hidden rounded border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-950">
        <ReadOnlyMessageStream payload={payload} />
      </section>
    </div>
  )
}

function ReadOnlyMessageStream({ payload }: { payload: SharedChatPayload }) {
  const items = renderChatMessages(payload.messages)
  const placeholderPayload = sharedChatRenderPayload(payload)
  const { t } = useT("chat")

  if (items.length === 0) {
    return (
      <div className="flex h-full min-h-0 items-center justify-center overflow-y-auto p-4 text-sm text-gray-500 dark:text-gray-400" data-testid="chat-message-stream">
        {t("no_shared_chat_messages")}
      </div>
    )
  }

  return (
    <div className="h-full min-h-0 space-y-4 overflow-y-auto p-3 sm:p-4" data-testid="chat-message-stream">
      {items.map((item) => item.type === "tool_group" ? (
        <ToolGroup item={item} key={renderItemKey(item)} />
      ) : (
        <ChatMessage item={item} key={renderItemKey(item)} payload={placeholderPayload} pendingActionIds={new Set()} prefix="" queryKey={chatQueryKey(payload.chat.id, "")} readOnly onNotice={() => undefined} />
      ))}
    </div>
  )
}

function sharedChatRenderPayload(payload: SharedChatPayload): ChatPayload {
  return {
    chat: {
      id: payload.chat.id,
      title: payload.chat.title,
      title_pending: false,
      pinned: false,
      pinned_context: null,
      chat_provider: "claude",
      chat_path: `/chats/shared/${payload.chat.id}`,
      repository: null,
      stop_requested_at: null,
      cumulative_input_tokens: 0,
      cumulative_output_tokens: 0,
      cumulative_cost_usd: 0
    },
    chat_available: false,
    turn_in_flight: false,
    agent_busy: false,
    switching_provider: false,
    has_more_older: false,
    messages: payload.messages,
    bookmarks: [],
    recent_chats: [],
    pending_actions: [],
    agent_questions: [],
    queued_messages: [],
    scratchpad_items: [],
    video_walkthroughs: [],
    attachment_groups: { repositories: [], epics: [], jobs: [], documents: [] },
    documents_in_scope: [],
    attachment_results: [],
    whiteboard: { version: 1, elements: [], appState: {}, files: {} },
    paths: {
      credentials_path: "/credentials",
      repositories_path: "/repositories",
      app_messages_path: "",
      app_message_path: "",
      app_rename_path: "",
      app_clear_path: "",
      app_branch_path: "",
      app_share_path: "",
      app_enqueue_message_path: "",
      app_stop_path: "",
      app_daemon_connection_path: "",
      app_bookmarks_path: "",
      app_attachments_path: "",
      app_video_walkthroughs_path: "",
      app_whiteboard_path: "",
      app_switch_provider_path: "",
      app_scratchpad_reorder_path: ""
    },
    gemini_configured: false,
    walkthroughs_enabled: false,
    coding_mode_enabled: false,
    local_mode_enabled: false,
    local_tunnel_connected: false
  }
}

function useChatVisualViewportStyle() {
  const [height, setHeight] = useState(visualViewportHeight)

  useEffect(() => {
    if (typeof window === "undefined" || !window.visualViewport) return

    const viewport = window.visualViewport
    const updateHeight = () => setHeight(visualViewportHeight())
    updateHeight()
    viewport.addEventListener("resize", updateHeight)
    viewport.addEventListener("scroll", updateHeight)
    return () => {
      viewport.removeEventListener("resize", updateHeight)
      viewport.removeEventListener("scroll", updateHeight)
    }
  }, [])

  if (height == null) return undefined

  return { "--chat-visual-viewport-height": `${height}px` } as CSSProperties
}

export function chatQueryKey(id: string | number, search: string): ChatQueryKey {
  return ["chats", String(id), search] as const
}

type BookmarkTarget = {
  messageId: number
  requestId: number
}

function ChatView({ chatId, payload, prefix, queryKey }: { chatId: string; payload: ChatPayload; prefix: string; queryKey: ChatQueryKey }) {
  const [notice, setNotice] = useState<string | null>(payload.message || null)
  const [whiteboardFullscreen, setWhiteboardFullscreen] = useState(false)
  const [settingsOpen, setSettingsOpen] = useState(false)
  const isDesktop = useMediaQuery("(min-width: 1024px)", true)
  const { t } = useT("chat")

  const title = chatDisplayTitle(payload.chat)

  useEffect(() => {
    setWhiteboardFullscreen(false)
  }, [payload.chat.id])

  useEffect(() => {
    if (!whiteboardFullscreen) return

    function handleKeyDown(event: globalThis.KeyboardEvent) {
      if (event.key === "Escape") setWhiteboardFullscreen(false)
    }

    window.addEventListener("keydown", handleKeyDown)
    return () => window.removeEventListener("keydown", handleKeyDown)
  }, [whiteboardFullscreen])

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-6">
      {whiteboardFullscreen || !isDesktop ? null : (
        <header className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h1 className={`break-words text-3xl font-semibold ${payload.chat.title_pending ? "animate-pulse text-gray-400 dark:text-gray-500" : "text-gray-900 dark:text-gray-100"}`}>{title}</h1>
            {payload.local_mode_enabled && payload.chat.mode === "local" && payload.chat.local_daemon_state === "connected" ? (
              <div className="mt-1 flex items-center gap-1.5 text-sm text-emerald-700 dark:text-emerald-400">
                <span aria-hidden="true" className="h-2 w-2 rounded-full bg-emerald-500" />
                <span>{t("local_daemon_connected", { repo: payload.chat.local_daemon_repo ?? "", branch: payload.chat.local_daemon_branch ?? "" })}</span>
              </div>
            ) : null}
          </div>
          <button
            aria-label={t("chat_settings")}
            className="rounded p-1.5 text-gray-400 transition hover:bg-gray-100 hover:text-gray-700 dark:text-gray-500 dark:hover:bg-gray-800 dark:hover:text-gray-300"
            onClick={() => setSettingsOpen(true)}
            title={t("chat_settings")}
            type="button"
          >
            <GearIcon className="h-5 w-5" />
          </button>
        </header>
      )}

      <NoticeToast message={notice} onDismiss={() => setNotice(null)} />

      {!payload.chat_available ? (
        <section className="rounded border border-amber-200 bg-white p-6 text-sm text-amber-900 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-100">
          <div className="font-semibold">{t("credentials_required_title")}</div>
          <p className="mt-1">Chat uses Claude. Add a Claude OAuth token in <Link className="underline hover:no-underline" to={withRoutePrefix("/credentials", prefix)}>Credentials</Link> to enable chat.</p>
        </section>
      ) : (
        <ChatWorkspace
          chatId={chatId}
          payload={payload}
          prefix={prefix}
          queryKey={queryKey}
          onNotice={setNotice}
          whiteboardFullscreen={whiteboardFullscreen}
          onWhiteboardFullscreenChange={setWhiteboardFullscreen}
          settingsOpen={settingsOpen}
          onSettingsOpenChange={setSettingsOpen}
        />
      )}
    </div>
  )
}

function MessageStream({ bookmarkTarget, payload, prefix, queryKey, onNotice }: { bookmarkTarget: BookmarkTarget | null; payload: ChatPayload; prefix: string; queryKey: ChatQueryKey; onNotice: (message: string | null) => void }) {
  const location = useLocation()
  const { t } = useT("chat")
  // Passive observer of the shared bootstrap cache (AppChrome owns the
  // fetch; flags also arrive via the inline syrus-bootstrap-data script) —
  // same pattern as useSetupStatus. An enabled query here would clobber the
  // seeded cache and double-fetch on every thread mount.
  const initialBootstrap = readInitialBootstrap()
  const bootstrap = useQuery({
    queryKey: ["bootstrap"],
    queryFn: fetchBootstrap,
    enabled: false,
    initialData: initialBootstrap ?? undefined,
    staleTime: initialBootstrap ? Number.POSITIVE_INFINITY : 0
  })
  const chatPolish = Boolean(bootstrap.data?.feature_flags?.chat_polish)
  const streamRef = useRef<HTMLDivElement | null>(null)
  const atBottomRef = useRef(true)
  const streamChatIdRef = useRef(payload.chat.id)
  const maxPayloadMessageIdRef = useRef(maxMessageId(payload.messages))
  // Frozen at mount / chat switch — the boundary between "history" and "new".
  const entranceBaselineMessageIdRef = useRef(maxMessageId(payload.messages))
  const bookmarkLoadBeforeRef = useRef<number | null>(null)
  const preserveScrollAfterOlderLoadRef = useRef<{ scrollHeight: number; scrollTop: number } | null>(null)
  const [newMessageCount, setNewMessageCount] = useState(0)
  const [olderMessages, setOlderMessages] = useState<ChatMessageItem[]>([])
  const [showSystemMessages, setShowSystemMessages] = useState(false)
  const [hasMoreOlder, setHasMoreOlder] = useState(payload.has_more_older)
  const [activeBookmarkTarget, setActiveBookmarkTarget] = useState<BookmarkTarget | null>(null)
  const displayedMessages = mergeChatMessages(olderMessages, payload.messages)
  const displayedItems = renderChatMessages(displayedMessages)
  const agentQuestions = payload.agent_questions || []
  const hiddenSystemMessageCount = displayedItems.filter(isLowPrioritySystemMessage).length
  const visibleItems = showSystemMessages ? displayedItems : displayedItems.filter((item) => !isLowPrioritySystemMessage(item))
  const pendingActionIds = new Set(payload.pending_actions.map((action) => action.id))
  const streamItems = injectTemporalMarkers(buildMessageStreamItems(visibleItems, payload.pending_actions))
  const agentActive = isAgentActive(payload)
  const oldestId = oldestMessageId(displayedMessages)
  const payloadMessageIdsSignature = payload.messages.map((message) => message.id).join("|")
  const visibleItemsSignature = chatStreamItemsSignature(streamItems)
  const loadOlder = useMutation({
    mutationFn: (before: number) => fetchChatMessages(payload.paths.app_messages_path, before),
    onSuccess: (page) => {
      setOlderMessages((current) => mergeChatMessages(page.messages, current))
      setHasMoreOlder(page.has_more_older)
    }
  })

  const scrollToBottom = useCallback(() => {
    scrollMessageStreamToBottom(streamRef.current, { smooth: chatPolish })
    atBottomRef.current = true
    setNewMessageCount(0)
  }, [chatPolish])

  const requestOlderMessages = useCallback((options: { preserveScroll: boolean }) => {
    if (!hasMoreOlder || oldestId == null || loadOlder.isPending) return false

    const stream = streamRef.current
    preserveScrollAfterOlderLoadRef.current = options.preserveScroll && stream ? {
      scrollHeight: stream.scrollHeight,
      scrollTop: stream.scrollTop
    } : null
    loadOlder.mutate(oldestId)
    return true
  }, [hasMoreOlder, loadOlder, oldestId])

  const handleScroll = useCallback((event: UIEvent<HTMLDivElement>) => {
    const atBottom = isMessageStreamAtBottom(event.currentTarget)
    atBottomRef.current = atBottom
    if (atBottom) setNewMessageCount(0)
    if (isMessageStreamNearTop(event.currentTarget)) {
      requestOlderMessages({ preserveScroll: true })
    }
  }, [requestOlderMessages])

  useEffect(() => {
    setOlderMessages([])
    setShowSystemMessages(false)
    setHasMoreOlder(payload.has_more_older)
    setNewMessageCount(0)
    atBottomRef.current = true
    streamChatIdRef.current = payload.chat.id
    maxPayloadMessageIdRef.current = maxMessageId(payload.messages)
    entranceBaselineMessageIdRef.current = maxMessageId(payload.messages)
  }, [payload.chat.id])

  useEffect(() => {
    if (olderMessages.length === 0) setHasMoreOlder(payload.has_more_older)
  }, [olderMessages.length, payload.has_more_older])

  useEffect(() => {
    if (streamChatIdRef.current !== payload.chat.id) {
      streamChatIdRef.current = payload.chat.id
      maxPayloadMessageIdRef.current = maxMessageId(payload.messages)
      return
    }

    const previousMaxMessageId = maxPayloadMessageIdRef.current
    const nextMaxMessageId = maxMessageId(payload.messages)
    if (previousMaxMessageId != null && nextMaxMessageId != null && nextMaxMessageId > previousMaxMessageId && !atBottomRef.current) {
      const incomingCount = countIncomingVisibleMessages(payload.messages, previousMaxMessageId, showSystemMessages)
      if (incomingCount > 0) setNewMessageCount((count) => count + incomingCount)
    }
    maxPayloadMessageIdRef.current = nextMaxMessageId
  }, [payload.chat.id, payloadMessageIdsSignature, showSystemMessages])

  useEffect(() => {
    if (atBottomRef.current) scrollMessageStreamToBottom(streamRef.current)
  }, [agentActive, visibleItemsSignature])

  useLayoutEffect(() => {
    const snapshot = preserveScrollAfterOlderLoadRef.current
    const stream = streamRef.current
    if (!snapshot || !stream) return

    stream.scrollTop = stream.scrollHeight - snapshot.scrollHeight + snapshot.scrollTop
    preserveScrollAfterOlderLoadRef.current = null
  }, [visibleItemsSignature])

  useEffect(() => {
    const stream = streamRef.current
    if (!stream || !messageStreamNeedsOlderMessages(stream)) return

    requestOlderMessages({ preserveScroll: false })
  }, [requestOlderMessages, visibleItemsSignature])

  useEffect(() => {
    if (!bookmarkTarget) return

    bookmarkLoadBeforeRef.current = null
    setActiveBookmarkTarget(bookmarkTarget)
  }, [bookmarkTarget?.messageId, bookmarkTarget?.requestId])

  useEffect(() => {
    const messageId = messageIdFromHash(location.hash)
    if (!messageId) return

    bookmarkLoadBeforeRef.current = null
    setActiveBookmarkTarget({ messageId, requestId: messageId })
  }, [location.hash, payload.chat.id])

  useEffect(() => {
    if (!activeBookmarkTarget) return

    const stream = streamRef.current
    if (!stream) return

    const target = findChatMessageAnchor(stream, activeBookmarkTarget.messageId)
    if (target) {
      scrollChatMessageIntoView(target)
      setActiveBookmarkTarget(null)
      return
    }

    if (!hasMoreOlder || oldestId == null) {
      setActiveBookmarkTarget(null)
      return
    }

    if (loadOlder.isPending || bookmarkLoadBeforeRef.current === oldestId) return

    bookmarkLoadBeforeRef.current = oldestId
    loadOlder.mutate(oldestId)
  }, [activeBookmarkTarget, hasMoreOlder, loadOlder.isPending, oldestId, visibleItemsSignature])

  if (displayedItems.length === 0 && payload.pending_actions.length === 0) {
    return (
      <div className="flex h-full min-h-0 flex-col gap-4 overflow-y-auto p-4 text-sm text-gray-500 dark:text-gray-400" data-testid="chat-message-stream">
        <div className="flex flex-1 flex-col items-center justify-center gap-3">
          <div>{payload.chat.repository ? t("empty_with_repo") : t("empty_without_repo")}</div>
          {payload.switching_provider ? <SwitchingProviderIndicator provider={payload.chat.chat_provider ?? ""} /> : agentActive ? <AgentActivityIndicator running={payload.agent_busy} /> : null}
        </div>
        {agentQuestions.length > 0 ? <AgentQuestions questions={agentQuestions} queryKey={queryKey} onNotice={onNotice} /> : null}
      </div>
    )
  }

  return (
    <div className="relative h-full min-h-0">
      <div className="h-full min-h-0 space-y-4 overflow-y-auto p-3 pt-12 sm:p-4 sm:pt-12" data-testid="chat-message-stream" onScroll={handleScroll} ref={streamRef}>
        {loadOlder.isPending ? <div className="text-center text-xs text-gray-400 dark:text-gray-500">{t("loading_older_messages")}</div> : null}
        {loadOlder.isError ? <div className="text-center text-xs text-red-700 dark:text-red-300">{errorMessage(loadOlder.error, t("error_load_older_messages"))}</div> : null}
        {hiddenSystemMessageCount > 0 ? (
          <SystemMessagesToggle count={hiddenSystemMessageCount} expanded={showSystemMessages} onToggle={() => setShowSystemMessages((value) => !value)} />
        ) : null}
        {streamItems.map((item) => item.type === "timestamp" ? (
          <MessageTimestamp fullDatetime={item.fullDatetime} key={renderItemKey(item)} time={item.time} />
        ) : item.type === "day_divider" ? (
          <DayDivider date={item.date} key={renderItemKey(item)} label={item.label} />
        ) : item.type === "pending_action" ? (
          <PendingActionCard pendingAction={pendingActionCardData(item.pendingAction)} key={renderItemKey(item)} queryKey={queryKey} onNotice={onNotice} />
        ) : item.type === "tool_group" ? (
          <ToolGroup item={item} key={renderItemKey(item)} />
        ) : (
          <ChatMessage animateIn={shouldAnimateMessageEntrance(chatPolish, item.id, entranceBaselineMessageIdRef.current)} item={item} key={renderItemKey(item)} payload={payload} pendingActionIds={pendingActionIds} prefix={prefix} queryKey={queryKey} onNotice={onNotice} />
        ))}
        {agentQuestions.length > 0 ? <AgentQuestions questions={agentQuestions} queryKey={queryKey} onNotice={onNotice} /> : null}
        {payload.switching_provider ? <SwitchingProviderIndicator provider={payload.chat.chat_provider ?? ""} /> : agentActive ? <AgentActivityIndicator running={payload.agent_busy} /> : null}
      </div>
      {newMessageCount > 0 ? (
        <button
          className="absolute bottom-4 left-1/2 -translate-x-1/2 rounded-full bg-gray-900 px-4 py-2 text-sm font-medium text-white shadow-lg hover:bg-gray-800 dark:bg-gray-100 dark:text-gray-950 dark:hover:bg-gray-200"
          onClick={scrollToBottom}
          type="button"
        >
          {t("new_messages_button", { count: newMessageCount })}
        </button>
      ) : null}
    </div>
  )
}

function MessageTimestamp({ time, fullDatetime }: { time: string; fullDatetime: string }) {
  return (
    <div className="flex justify-center py-1" title={fullDatetime}>
      <span className="text-xs text-gray-400 dark:text-gray-500">{time}</span>
    </div>
  )
}

function DayDivider({ date: _date, label }: { date: string; label: string }) {
  const id = useId()

  return (
    <div className="flex items-center gap-3 py-3">
      <WaveLine patternId={`wave-${id}-left`} />
      <span className="whitespace-nowrap text-xs text-gray-300 dark:text-gray-700">{label}</span>
      <WaveLine patternId={`wave-${id}-right`} />
    </div>
  )
}

function WaveLine({ patternId }: { patternId: string }) {
  return (
    <svg className="h-[8px] flex-1 text-gray-300 dark:text-gray-700" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <pattern height="8" id={patternId} patternUnits="userSpaceOnUse" width="20" x="0" y="0">
          <path d="M0,4 C5,0 10,8 15,4 C20,0 25,8 30,4" fill="none" stroke="currentColor" strokeWidth="1.5" />
        </pattern>
      </defs>
      <rect fill={`url(#${patternId})`} height="100%" width="100%" />
    </svg>
  )
}

function SystemMessagesToggle({ count, expanded, onToggle }: { count: number; expanded: boolean; onToggle: () => void }) {
  const { t } = useT("chat")
  return (
    <div className="flex justify-center">
      <button className="rounded-full border border-gray-200 bg-white px-3 py-1 text-xs font-medium text-gray-600 shadow-sm hover:bg-gray-50 dark:border-gray-700 dark:bg-gray-900 dark:text-gray-300 dark:hover:bg-gray-800" onClick={onToggle} type="button">
        {expanded ? t("hide_system_messages") : t("show_system_messages", { count })}
      </button>
    </div>
  )
}

const WORKING_PHRASES = [
  { latin: "Cogitans", english: "thinking it through" },
  { latin: "Machinans", english: "contriving, plotting" },
  { latin: "Moliens", english: "striving, setting in motion" },
  { latin: "Meditans", english: "planning, turning over in the mind" },
  { latin: "Excogitans", english: "thinking out, devising" },
  { latin: "Elaborans", english: "working it out carefully" },
  { latin: "Perscrutans", english: "examining thoroughly" },
  { latin: "Computans", english: "calculating" },
  { latin: "Conficiens", english: "bringing to completion" },
  { latin: "Agitans", english: "setting things in motion" },
  { latin: "Evolvens", english: "unrolling, unfolding" },
  { latin: "Ponderans", english: "weighing carefully" },
  { latin: "Consilians", english: "taking counsel, deliberating" },
  { latin: "Exsequens", english: "carrying out, executing" },
  { latin: "Investigans", english: "tracking down, hunting through" },
  { latin: "Versans", english: "turning over in the mind" },
  { latin: "Struens", english: "building, constructing" },
  { latin: "Nectens", english: "weaving together, binding" },
  { latin: "Vigilans", english: "keeping watch" },
  { latin: "Expediens", english: "making ready, dispatching" }
] as const

export function getStartingPhrase() {
  const now = new Date()
  if (now.getMonth() === 2 && now.getDate() === 15) {
    return { latin: "Cave, Idus Martias.", english: "Beware the Ides of March." }
  }
  return { latin: "Accingitur", english: "girding itself" }
}

function AgentActivityIndicator({ running }: { running: boolean }) {
  const workingPhrase = useMemo(
    () => WORKING_PHRASES[Math.floor(Math.random() * WORKING_PHRASES.length)],
    []
  )
  const phrase = running ? workingPhrase : getStartingPhrase()

  return (
    <div aria-label={phrase.english} aria-live="polite" className="flex justify-start" role="status">
      <div className="inline-flex items-center gap-2 rounded-full border border-blue-100 bg-blue-50 px-3 py-1.5 text-xs font-medium text-blue-700 shadow-sm dark:border-blue-900 dark:bg-blue-950 dark:text-blue-200">
        <span aria-hidden="true" className="inline-flex items-center gap-1">
          {[0, 1, 2].map((index) => (
            <span
              className="h-1.5 w-1.5 animate-bounce rounded-full bg-blue-500 dark:bg-blue-300"
              key={index}
              style={{ animationDelay: `${index * 140}ms` }}
            />
          ))}
        </span>
        <span title={phrase.english}>{phrase.latin}</span>
      </div>
    </div>
  )
}

function SwitchingProviderIndicator({ provider }: { provider: string }) {
  const { t } = useT("chat")
  const label = t("switching_to_provider", { provider: providerLabel(provider) })
  return (
    <div aria-label={label} aria-live="polite" className="flex justify-start" role="status">
      <div className="inline-flex items-center gap-2 rounded-full border border-amber-100 bg-amber-50 px-3 py-1.5 text-xs font-medium text-amber-700 shadow-sm dark:border-amber-900 dark:bg-amber-950 dark:text-amber-200">
        <span aria-hidden="true" className="inline-flex items-center gap-1">
          {[0, 1, 2].map((index) => (
            <span
              className="h-1.5 w-1.5 animate-bounce rounded-full bg-amber-500 dark:bg-amber-300"
              key={index}
              style={{ animationDelay: `${index * 140}ms` }}
            />
          ))}
        </span>
        <span>{label}</span>
      </div>
    </div>
  )
}


function useMediaQuery(query: string, defaultMatches: boolean) {
  const [matches, setMatches] = useState(() => {
    if (typeof window === "undefined" || typeof window.matchMedia !== "function") return defaultMatches

    return window.matchMedia(query).matches
  })

  useEffect(() => {
    if (typeof window === "undefined" || typeof window.matchMedia !== "function") return

    const media = window.matchMedia(query)
    const updateMatches = () => setMatches(media.matches)
    updateMatches()

    if (typeof media.addEventListener === "function") {
      media.addEventListener("change", updateMatches)
      return () => media.removeEventListener("change", updateMatches)
    }

    media.addListener(updateMatches)
    return () => media.removeListener(updateMatches)
  }, [query])

  return matches
}


function ChatWorkspace({
  chatId,
  payload,
  prefix,
  queryKey,
  onNotice,
  whiteboardFullscreen,
  onWhiteboardFullscreenChange,
  settingsOpen,
  onSettingsOpenChange
}: {
  chatId: string
  payload: ChatPayload
  prefix: string
  queryKey: ChatQueryKey
  onNotice: (message: string | null) => void
  whiteboardFullscreen: boolean
  onWhiteboardFullscreenChange: (fullscreen: boolean) => void
  settingsOpen: boolean
  onSettingsOpenChange: (open: boolean) => void
}) {
  const [activeTab, setActiveTab] = useState<WorkspaceTab>(() => storedWorkspaceTab() || defaultWorkspaceTab(payload))
  const [activeMobileTab, setActiveMobileTab] = useState<MobileChatTab>("chat")
  const [workspaceWidth, setWorkspaceWidth] = useState(storedWorkspaceWidth)
  const [panelCollapsed, setPanelCollapsed] = useState(storedWorkspaceCollapsed)
  const [bookmarkTarget, setBookmarkTarget] = useState<BookmarkTarget | null>(null)
  const [bookmarkPickerOpen, setBookmarkPickerOpen] = useState(false)
  const bookmarkRequestIdRef = useRef(0)
  const handledMessageDeepLinkRef = useRef<string | null>(null)
  const navigate = useNavigate()
  const isDesktop = useMediaQuery("(min-width: 1024px)", true)
  const { t } = useT("chat")
  const expanded = activeTab === "whiteboard" && whiteboardFullscreen

  useEffect(() => {
    storeWorkspacePreference(CHAT_WORKSPACE_TAB_KEY, activeTab)
  }, [activeTab])

  useEffect(() => {
    storeWorkspacePreference(CHAT_WORKSPACE_WIDTH_KEY, String(workspaceWidth))
  }, [workspaceWidth])

  useEffect(() => {
    storeWorkspacePreference(CHAT_WORKSPACE_COLLAPSED_KEY, String(panelCollapsed))
  }, [panelCollapsed])

  function beginResize(event: ReactMouseEvent<HTMLButtonElement>) {
    event.preventDefault()
    const startX = event.clientX
    const startWidth = workspaceWidth

    function resize(moveEvent: MouseEvent) {
      setWorkspaceWidth(clampWorkspaceWidth(startWidth - (moveEvent.clientX - startX)))
    }

    function stopResize() {
      window.removeEventListener("mousemove", resize)
      window.removeEventListener("mouseup", stopResize)
    }

    window.addEventListener("mousemove", resize)
    window.addEventListener("mouseup", stopResize)
  }

  function selectTab(tab: WorkspaceTab) {
    if (tab !== "whiteboard") onWhiteboardFullscreenChange(false)
    setActiveTab(tab)
  }

  function selectMobileTab(tab: MobileChatTab) {
    setActiveMobileTab(tab)
    if (tab === "chat") {
      onWhiteboardFullscreenChange(false)
      return
    }

    selectTab(tab)
  }

  function selectBookmark(messageId: number) {
    onWhiteboardFullscreenChange(false)
    setActiveMobileTab("chat")
    bookmarkRequestIdRef.current += 1
    setBookmarkTarget({ messageId, requestId: bookmarkRequestIdRef.current })
  }

  useEffect(() => {
    const searchParams = new URLSearchParams(queryKey[2])
    const messageId = Number.parseInt(searchParams.get("message_id") || "", 10)
    if (!Number.isFinite(messageId) || messageId <= 0) return

    const deepLinkKey = `${payload.chat.id}:${messageId}`
    if (handledMessageDeepLinkRef.current === deepLinkKey) return

    handledMessageDeepLinkRef.current = deepLinkKey
    selectBookmark(messageId)
    searchParams.delete("message_id")
    const nextSearch = searchParams.toString()
    navigate({ search: nextSearch ? `?${nextSearch}` : "" }, { replace: true })
  }, [navigate, payload.chat.id, queryKey])

  const commandHandlers: ChatSystemCommandHandlers = {
    openBookmarks: () => {
      onWhiteboardFullscreenChange(false)
      setBookmarkPickerOpen(true)
    },
    openAttachments: () => {
      onWhiteboardFullscreenChange(false)
      setActiveTab("context")
      setActiveMobileTab("context")
    },
    openSettings: () => onSettingsOpenChange(true)
  }

  if (!isDesktop && !expanded) {
    return (
      <div className="flex min-h-0 flex-1 flex-col bg-white dark:bg-gray-950">
        <nav aria-label={t("aria_mobile_tabs")} className="flex shrink-0 overflow-x-auto border-b border-gray-200 px-2 pt-2 text-sm font-medium dark:border-gray-700">
          {(["chat", "whiteboard", "context", "media", ...(codingFilesTabVisible(payload) ? (["files"] as MobileChatTab[]) : []), ...(payload.local_tunnel_connected ? (["diff"] as MobileChatTab[]) : []), ...(jobsTabVisible(payload) ? (["jobs"] as MobileChatTab[]) : [])] as MobileChatTab[]).map((tab) => (
            <button
              className={workspaceTabClass(activeMobileTab === tab)}
              key={tab}
              onClick={() => selectMobileTab(tab)}
              type="button"
            >
              {mobileChatTabLabel(tab)}
            </button>
          ))}
        </nav>
        <div className="flex min-h-0 w-full flex-1">
          {activeMobileTab === "chat" ? (
            <ChatColumn bookmarkTarget={bookmarkTarget} chatId={chatId} commandHandlers={commandHandlers} payload={payload} prefix={prefix} queryKey={queryKey} onNotice={onNotice} />
          ) : (
            <ChatWorkspacePanel
              activeTab={activeTab}
              fullscreen={false}
              showTabs={false}
              onSelectTab={selectTab}
              onToggleWhiteboardFullscreen={() => onWhiteboardFullscreenChange(true)}
              payload={payload}
              prefix={prefix}
              queryKey={queryKey}
              onNotice={onNotice}
              onBookmarkSelect={selectBookmark}
            />
          )}
        </div>
        {settingsOpen ? <ChatSettingsDialog payload={payload} prefix={prefix} queryKey={queryKey} onClose={() => onSettingsOpenChange(false)} /> : null}
        {bookmarkPickerOpen ? <BookmarkPickerModal bookmarks={payload.bookmarks} onClose={() => setBookmarkPickerOpen(false)} onSelect={selectBookmark} /> : null}
      </div>
    )
  }

  return (
    <div
      className={expanded ? "flex min-h-0 flex-1 flex-col" : "flex min-h-0 flex-1 flex-col gap-4 lg:grid lg:gap-0"}
      style={
        expanded
          ? undefined
          : {
              gridTemplateColumns: panelCollapsed
                ? "minmax(0,1fr) 0 2.5rem"
                : `minmax(0,1fr) 0.5rem minmax(${CHAT_WORKSPACE_MIN_WIDTH}px,${workspaceWidth}px)`,
              transition: "grid-template-columns 150ms ease"
            }
      }
    >
      {expanded ? null : <ChatColumn bookmarkTarget={bookmarkTarget} chatId={chatId} commandHandlers={commandHandlers} payload={payload} prefix={prefix} queryKey={queryKey} onNotice={onNotice} />}
      {expanded || panelCollapsed ? null : (
        <button
          aria-label={t("resize_workspace")}
          className="hidden cursor-col-resize rounded bg-transparent transition hover:bg-blue-100 focus:bg-blue-100 focus:outline-none lg:block dark:hover:bg-blue-950 dark:focus:bg-blue-950"
          onMouseDown={beginResize}
          type="button"
        />
      )}
      {!expanded && panelCollapsed ? (
        <div className="hidden lg:flex lg:flex-col lg:items-start lg:pt-3">
          <button
            aria-label={t("open_workspace")}
            className="rounded p-1.5 text-gray-400 transition hover:bg-gray-100 hover:text-gray-700 dark:text-gray-500 dark:hover:bg-gray-800 dark:hover:text-gray-300"
            onClick={() => setPanelCollapsed(false)}
            title={t("open_panel")}
            type="button"
          >
            <svg aria-hidden="true" className="h-4 w-4" fill="none" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
              <rect height="18" rx="2" ry="2" width="18" x="3" y="3" />
              <line x1="15" x2="15" y1="3" y2="21" />
              <polyline points="12 9 15 12 12 15" />
            </svg>
          </button>
        </div>
      ) : null}
      {expanded || !panelCollapsed ? (
        <ChatWorkspacePanel
          activeTab={activeTab}
          fullscreen={expanded}
          onSelectTab={selectTab}
          onToggleCollapse={expanded ? undefined : () => setPanelCollapsed(true)}
          onToggleWhiteboardFullscreen={() => onWhiteboardFullscreenChange(!expanded)}
          payload={payload}
          prefix={prefix}
          queryKey={queryKey}
          onNotice={onNotice}
          onBookmarkSelect={selectBookmark}
        />
      ) : null}
      {settingsOpen ? <ChatSettingsDialog payload={payload} prefix={prefix} queryKey={queryKey} onClose={() => onSettingsOpenChange(false)} /> : null}
      {bookmarkPickerOpen ? <BookmarkPickerModal bookmarks={payload.bookmarks} onClose={() => setBookmarkPickerOpen(false)} onSelect={selectBookmark} /> : null}
    </div>
  )
}

function BookmarkPickerModal({ bookmarks, onClose, onSelect }: { bookmarks: ChatBookmark[]; onClose: () => void; onSelect: (messageId: number) => void }) {
  const { t } = useT("chat")
  function selectBookmark(bookmark: ChatBookmark) {
    onSelect(bookmark.anchor_message_id ?? bookmark.chat_message_id)
    onClose()
  }

  return (
    <div className="fixed inset-0 z-40 flex items-center justify-center bg-gray-950/35 p-4" onClick={onClose} role="presentation">
      <section aria-labelledby="bookmark-picker-title" aria-modal="true" className="w-full max-w-md rounded border border-gray-200 bg-white shadow-xl dark:border-gray-700 dark:bg-gray-900" onClick={(event) => event.stopPropagation()} role="dialog">
        <header className="flex items-center justify-between border-b border-gray-200 px-4 py-3 dark:border-gray-700">
          <h2 className="text-base font-semibold text-gray-900 dark:text-gray-100" id="bookmark-picker-title">{t("bookmarks")}</h2>
          <button
            aria-label={t("close_bookmarks")}
            className="rounded p-1 text-gray-500 hover:bg-gray-100 hover:text-gray-700 focus:outline-none focus:ring-2 focus:ring-blue-500 dark:text-gray-400 dark:hover:bg-gray-800 dark:hover:text-gray-200"
            onClick={onClose}
            type="button"
          >
            <CloseIcon className="h-4 w-4" />
          </button>
        </header>
        <div className="max-h-[min(24rem,calc(100dvh-10rem))] overflow-y-auto p-2">
          {bookmarks.length === 0 ? (
            <div className="px-2 py-6 text-center text-sm text-gray-500 dark:text-gray-400">{t("no_bookmarks")}</div>
          ) : (
            <div className="space-y-1">
              {bookmarks.map((bookmark) => (
                <button
                  className="flex w-full items-center gap-3 rounded px-3 py-2 text-left text-sm text-gray-800 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-blue-500 dark:text-gray-100 dark:hover:bg-gray-800"
                  key={bookmark.id}
                  onClick={() => selectBookmark(bookmark)}
                  type="button"
                >
                  <span aria-hidden="true" className="h-1.5 w-1.5 shrink-0 rounded-full bg-gray-400 dark:bg-gray-500" />
                  <span className="min-w-0 break-words">{bookmark.label}</span>
                </button>
              ))}
            </div>
          )}
        </div>
      </section>
    </div>
  )
}

function CodingCheckoutBanner({ payload, queryKey, onNotice }: { payload: ChatPayload; queryKey: ChatQueryKey; onNotice: (message: string | null) => void }) {
  const { t } = useT("chat")
  const queryClient = useQueryClient()
  const cancelPath = payload.paths.app_cancel_coding_checkout_path
  const cancel = useMutation({
    mutationFn: () => cancelCodingCheckout(cancelPath!),
    onSuccess: (updated) => {
      queryClient.setQueryData<ChatPayload>(queryKey, updated)
      onNotice(t("coding_checkout_cancelled_notice"))
    },
    onError: () => {
      onNotice(t("coding_checkout_cancel_error"))
    }
  })

  if (!payload.coding_mode_enabled || !payload.chat.coding_checkout_uncommitted || !cancelPath) return null

  return (
    <div className="flex items-center justify-between rounded border border-amber-200 bg-amber-50 px-3 py-2 text-sm text-amber-900 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-100">
      <span>{t("coding_checkout_uncommitted_banner")}</span>
      <button
        className="shrink-0 font-medium underline hover:no-underline disabled:cursor-not-allowed disabled:no-underline disabled:opacity-50"
        disabled={cancel.isPending}
        onClick={() => cancel.mutate()}
        type="button"
      >
        {t("cancel_coding_checkout")}
      </button>
    </div>
  )
}

function ChatColumn({ bookmarkTarget, chatId, commandHandlers, payload, prefix, queryKey, onNotice }: { bookmarkTarget: BookmarkTarget | null; chatId: string; commandHandlers: ChatSystemCommandHandlers; payload: ChatPayload; prefix: string; queryKey: ChatQueryKey; onNotice: (message: string | null) => void }) {
  const [hasSentFirstMessage, setHasSentFirstMessage] = useState(false)
  const { t } = useT("chat")
  const landing = payload.messages.length === 0 && payload.pending_actions.length === 0 && !hasSentFirstMessage

  useEffect(() => {
    setHasSentFirstMessage(false)
  }, [payload.chat.id])

  return (
    <section className={`flex min-h-0 min-w-0 flex-1 flex-col transition-all duration-500 ${landing ? "items-center justify-center gap-6 px-4" : "gap-3"}`}>
      {landing ? (
        <h1 className="text-center text-3xl font-semibold tracking-normal text-gray-950 sm:text-4xl dark:text-gray-100">{t("landing_prompt")}</h1>
      ) : null}
      {payload.local_mode_enabled && payload.chat.mode === "local" ? (
        <LocalDaemonBanner payload={payload} />
      ) : null}
      <div className={`relative min-h-0 overflow-hidden rounded border border-gray-200 bg-white transition-all duration-500 ease-out dark:border-gray-700 dark:bg-gray-950 ${landing ? "h-0 w-full max-w-2xl opacity-0" : "flex-1 opacity-100"}`}>
        <MessageStream bookmarkTarget={bookmarkTarget} payload={payload} prefix={prefix} queryKey={queryKey} onNotice={onNotice} />
        <UsageOverlay payload={payload} />
      </div>
      <div className={landing ? "w-full max-w-sm sm:max-w-2xl" : "space-y-3"}>
        {!landing ? <CodingCheckoutBanner payload={payload} queryKey={queryKey} onNotice={onNotice} /> : null}
        <Compose key={chatId} autoFocus={landing} chatId={chatId} commandHandlers={commandHandlers} payload={payload} prefix={prefix} queryKey={queryKey} showAttachedRepositories={landing} onNotice={onNotice} onMessageSent={() => setHasSentFirstMessage(true)} />
      </div>
    </section>
  )
}

function LocalDaemonBanner({ payload }: { payload: ChatPayload }) {
  const { t } = useT("chat")
  const [copied, setCopied] = useState(false)
  const copyTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  useEffect(() => () => { if (copyTimeoutRef.current) clearTimeout(copyTimeoutRef.current) }, [])

  function copyCommand() {
    void navigator.clipboard.writeText(t("local_daemon_command")).then(() => {
      setCopied(true)
      copyTimeoutRef.current = setTimeout(() => setCopied(false), 2000)
    })
  }

  const daemonState = payload.chat.local_daemon_state ?? null

  if (daemonState === "connected") return null

  if (daemonState === "disconnected") {
    return (
      <section className="rounded border border-amber-200 bg-white p-4 text-sm text-amber-900 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-100">
        <div className="font-semibold">{t("local_daemon_disconnected_title")}</div>
        <p className="mt-1">{t("local_daemon_disconnected_body")}</p>
      </section>
    )
  }

  return (
    <section className="rounded border border-gray-200 bg-gray-50 p-4 text-sm text-gray-700 dark:border-gray-700 dark:bg-gray-900 dark:text-gray-300">
      <div className="font-semibold">{t("local_daemon_not_connected_title")}</div>
      <p className="mt-1">{t("local_daemon_not_connected_body")}</p>
      <div className="mt-3 flex items-center gap-2">
        <code className="rounded bg-gray-100 px-2 py-1 font-mono text-xs text-gray-800 dark:bg-gray-800 dark:text-gray-200">{t("local_daemon_command")}</code>
        <button
          className="rounded border border-gray-300 bg-white px-2 py-1 text-xs font-medium text-gray-600 transition hover:bg-gray-50 hover:text-gray-800 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-300 dark:hover:bg-gray-700 dark:hover:text-gray-100"
          onClick={copyCommand}
          type="button"
        >
          {copied ? t("local_daemon_copied") : t("local_daemon_copy")}
        </button>
      </div>
    </section>
  )
}

function AgentQuestions({ questions, queryKey, onNotice }: { questions: ChatAgentQuestion[]; queryKey: ChatQueryKey; onNotice: (message: string | null) => void }) {
  const { t } = useT("chat")
  return (
    <section aria-label={t("aria_agent_questions")} className="w-full max-w-3xl space-y-3 rounded border border-blue-200 bg-blue-50 p-3 dark:border-blue-800 dark:bg-blue-950/60">
      {questions.map((question) => <AgentQuestionPrompt key={question.id} question={question} queryKey={queryKey} onNotice={onNotice} />)}
    </section>
  )
}

function AgentQuestionPrompt({ question, queryKey, onNotice }: { question: ChatAgentQuestion; queryKey: ChatQueryKey; onNotice: (message: string | null) => void }) {
  const { t } = useT("chat")
  const queryClient = useQueryClient()
  const search = queryKey[2]
  const [answer, setAnswer] = useState("")
  const submit = useMutation({
    mutationFn: (value: string) => answerAgentQuestion(appendSearch(question.app_answer_path, search), value),
    onSuccess: (updated) => {
      queryClient.setQueryData(queryKey, updated)
      setAnswer("")
      onNotice(updated.message || null)
    }
  })
  const options = question.options?.filter((option) => option.trim().length > 0) || []

  function submitText(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const value = answer.trim()
    if (value.length === 0 || submit.isPending) return

    submit.mutate(value)
  }

  function declineAnswer() {
    if (submit.isPending) return

    submit.mutate("I decline to answer.")
  }

  return (
    <div className="space-y-3 rounded border border-blue-200 bg-white p-3 text-sm dark:border-blue-800 dark:bg-gray-950">
      <div className="font-medium text-gray-900 dark:text-gray-100">{question.question}</div>
      {submit.isError ? <div className="text-xs text-red-700 dark:text-red-300">{errorMessage(submit.error, "Answer could not be submitted.")}</div> : null}
      {options.length > 0 ? (
        <div className="flex flex-col gap-2">
          {options.map((option) => (
            <button className={`${secondaryButton()} flex w-full justify-start text-left`} disabled={submit.isPending} key={option} onClick={() => submit.mutate(option)} type="button">
              {option}
            </button>
          ))}
        </div>
      ) : null}
      <form className="flex flex-col gap-2 sm:flex-row" onSubmit={submitText}>
        <input
          aria-label={t("aria_custom_answer")}
          className="min-h-9 flex-1 rounded border border-gray-300 px-3 py-2 text-base focus:border-blue-500 focus:ring-blue-500 sm:text-sm dark:border-gray-600 dark:bg-gray-950 dark:text-gray-100"
          disabled={submit.isPending}
          onChange={(event) => setAnswer(event.target.value)}
          placeholder={t("ph_custom_response")}
          value={answer}
        />
        <button className={primaryButton()} disabled={submit.isPending || answer.trim().length === 0} type="submit">{t("submit")}</button>
      </form>
      <button className={`${secondaryButton()} flex w-full justify-start text-left`} disabled={submit.isPending} onClick={declineAnswer} type="button">
        Decline to answer
      </button>
    </div>
  )
}

function ChatWorkspacePanel({
  activeTab,
  fullscreen,
  showTabs = true,
  onSelectTab,
  onToggleCollapse,
  onToggleWhiteboardFullscreen,
  payload,
  prefix,
  queryKey,
  onNotice,
  onBookmarkSelect
}: {
  activeTab: WorkspaceTab
  fullscreen: boolean
  showTabs?: boolean
  onSelectTab: (tab: WorkspaceTab) => void
  onToggleCollapse?: () => void
  onToggleWhiteboardFullscreen: () => void
  payload: ChatPayload
  prefix: string
  queryKey: ChatQueryKey
  onNotice: (message: string | null) => void
  onBookmarkSelect: (messageId: number) => void
}) {
  const { t } = useT("chat")
  return (
    <aside aria-label={t("aria_chat_workspace")} className={`flex min-h-0 min-w-0 flex-1 flex-col rounded border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-900 ${fullscreen ? "" : "h-full w-full"}`}>
      {fullscreen || !showTabs ? null : (
        <nav aria-label={t("aria_workspace_tabs")} className="flex items-center border-b border-gray-200 px-3 pt-3 text-sm font-medium dark:border-gray-700">
          {(["whiteboard", "context", "media", ...(codingFilesTabVisible(payload) ? (["files"] as WorkspaceTab[]) : []), ...(payload.local_tunnel_connected ? (["diff"] as WorkspaceTab[]) : []), ...(jobsTabVisible(payload) ? (["jobs"] as WorkspaceTab[]) : [])] as WorkspaceTab[]).map((tab) => (
            <button
              className={workspaceTabClass(activeTab === tab)}
              key={tab}
              onClick={() => onSelectTab(tab)}
              type="button"
            >
              {workspaceTabLabel(tab)}
            </button>
          ))}
          {onToggleCollapse ? (
            <button
              aria-label={t("aria_close_workspace")}
              className="ml-auto self-center rounded p-1.5 text-gray-400 transition hover:bg-gray-100 hover:text-gray-700 dark:text-gray-500 dark:hover:bg-gray-800 dark:hover:text-gray-300"
              onClick={onToggleCollapse}
              title={t("aria_close_panel")}
              type="button"
            >
              <svg aria-hidden="true" className="h-4 w-4" fill="none" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
                <rect height="18" rx="2" ry="2" width="18" x="3" y="3" />
                <line x1="15" x2="15" y1="3" y2="21" />
                <polyline points="18 9 15 12 18 15" />
              </svg>
            </button>
          ) : null}
        </nav>
      )}
      <div className={`min-h-0 flex-1 ${activeTab === "whiteboard" ? "overflow-hidden p-3" : activeTab === "files" ? "overflow-hidden" : "overflow-y-auto p-4"}`}>
        {activeTab === "whiteboard" ? (
          <WhiteboardBoundary>
            <WhiteboardPanel fullscreen={fullscreen} onToggleFullscreen={onToggleWhiteboardFullscreen} payload={payload} />
          </WhiteboardBoundary>
        ) : null}
        {activeTab === "context" ? <Attachments payload={payload} prefix={prefix} queryKey={queryKey} onNotice={onNotice} /> : null}
        {activeTab === "media" ? <MediaGallery messages={payload.messages} payload={payload} queryKey={queryKey} onNotice={onNotice} /> : null}
        {activeTab === "files" ? <CodingFilesPanel payload={payload} /> : null}
        {activeTab === "diff" && payload.local_tunnel_connected ? <LocalDiffPanel /> : null}
        {activeTab === "jobs" ? <ChatJobStatusPanel chatId={payload.chat.id} /> : null}
      </div>
    </aside>
  )
}

type DiffMode = "head" | "staged"

type LocalDiffState = {
  diff: string | null
  mode: DiffMode
  loading: boolean
  error: string | null
}

function renderUnifiedDiff(diff: string): ReactNode[] {
  const nodes: ReactNode[] = []
  diff.split("\n").forEach((line, index) => {
    let className: string
    if (line.startsWith("+++") || line.startsWith("---")) {
      className = "text-gray-500 dark:text-gray-400"
    } else if (line.startsWith("@@")) {
      className = "text-blue-600 dark:text-blue-400"
    } else if (line.startsWith("+")) {
      className = "bg-emerald-50 text-emerald-800 dark:bg-emerald-950 dark:text-emerald-300"
    } else if (line.startsWith("-")) {
      className = "bg-red-50 text-red-800 dark:bg-red-950 dark:text-red-300"
    } else if (line.startsWith("diff ") || line.startsWith("index ")) {
      className = "font-semibold text-gray-700 dark:text-gray-300"
    } else {
      className = "text-gray-700 dark:text-gray-300"
    }
    nodes.push(
      <div className={`block whitespace-pre ${className}`} key={index}>
        {line || " "}
      </div>
    )
  })
  return nodes
}

function LocalDiffPanel() {
  const { t } = useT("chat")
  const [state, setState] = useState<LocalDiffState>({ diff: null, mode: "head", loading: true, error: null })
  const subscriptionRef = useRef<Subscription | null>(null)

  useEffect(() => {
    const sub = createConsumer().subscriptions.create(
      { channel: "LocalDiffChannel" },
      {
        connected() {
          // Initial diff requested automatically by channel on subscribe.
        },
        received(data: { type?: string; diff?: string | null; mode?: string; error?: string | null }) {
          if (data.type !== "diff_result") return
          const mode: DiffMode = data.mode === "staged" ? "staged" : "head"
          setState({ diff: data.diff ?? null, mode, loading: false, error: data.error ?? null })
        }
      }
    )
    subscriptionRef.current = sub
    return () => sub.unsubscribe()
  }, [])

  function refresh(mode: DiffMode) {
    setState((s) => ({ ...s, loading: true, error: null }))
    subscriptionRef.current?.perform("receive", { mode })
  }

  const { diff, mode, loading, error } = state
  const isEmpty = !loading && !error && (diff === null || diff === "")

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center justify-between gap-2">
        <div className="flex gap-1 rounded border border-gray-200 p-0.5 dark:border-gray-700">
          <button
            className={`rounded px-2 py-0.5 text-xs font-medium transition ${mode === "head" ? "bg-gray-900 text-white dark:bg-gray-100 dark:text-gray-900" : "text-gray-600 hover:text-gray-900 dark:text-gray-400 dark:hover:text-gray-100"}`}
            disabled={loading}
            onClick={() => refresh("head")}
            type="button"
          >
            HEAD
          </button>
          <button
            className={`rounded px-2 py-0.5 text-xs font-medium transition ${mode === "staged" ? "bg-gray-900 text-white dark:bg-gray-100 dark:text-gray-900" : "text-gray-600 hover:text-gray-900 dark:text-gray-400 dark:hover:text-gray-100"}`}
            disabled={loading}
            onClick={() => refresh("staged")}
            type="button"
          >
            Staged
          </button>
        </div>
        <button
          aria-label={t("aria_refresh_diff")}
          className="rounded p-1 text-gray-400 transition hover:bg-gray-100 hover:text-gray-700 disabled:cursor-not-allowed disabled:opacity-50 dark:text-gray-500 dark:hover:bg-gray-800 dark:hover:text-gray-300"
          disabled={loading}
          onClick={() => refresh(mode)}
          title={t("aria_refresh")}
          type="button"
        >
          <svg aria-hidden="true" className={`h-4 w-4 ${loading ? "animate-spin" : ""}`} fill="none" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
            <path d="M23 4v6h-6" />
            <path d="M1 20v-6h6" />
            <path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15" />
          </svg>
        </button>
      </div>

      {loading && diff === null ? (
        <p className="text-sm text-gray-500 dark:text-gray-400">Loading diff…</p>
      ) : error ? (
        <p className="text-sm text-red-600 dark:text-red-400">
          {error === "not_connected" ? "Daemon not connected." : `Error: ${error}`}
        </p>
      ) : isEmpty ? (
        <p className="text-sm text-gray-500 dark:text-gray-400">
          {mode === "staged" ? "No staged changes." : "No uncommitted changes."}
        </p>
      ) : (
        <div className="overflow-x-auto rounded border border-gray-200 bg-gray-50 dark:border-gray-700 dark:bg-gray-950">
          <code className="block p-3 font-mono text-xs leading-5">
            {renderUnifiedDiff(diff!)}
          </code>
        </div>
      )}
    </div>
  )
}

function MediaGallery({ messages, payload, queryKey, onNotice }: { messages: ChatRenderItem[]; payload: ChatPayload; queryKey: ChatQueryKey; onNotice: (message: string | null) => void }) {
  const { t } = useT("chat")
  const images = imageAttachments(messages)
  const walkthroughs = payload.video_walkthroughs || []
  const walkthroughStateLabel = (state: string) =>
    ({ uploaded: t("walkthrough_state_uploaded"), analyzing: t("walkthrough_state_analyzing"), analyzed: t("walkthrough_state_analyzed"), failed: t("walkthrough_state_failed") } as Record<string, string>)[state] || state
  const [lightboxImage, setLightboxImage] = useState<ChatMessageImageAttachment | null>(null)
  const [loadingSnapshotId, setLoadingSnapshotId] = useState<number | null>(null)
  const [snapshotError, setSnapshotError] = useState<string | null>(null)
  const queryClient = useQueryClient()
  const snapshots = useQuery({
    queryKey: ["whiteboard_snapshots", String(payload.chat.id)],
    queryFn: () => fetchWhiteboardSnapshots(payload.chat.id),
    enabled: payload.chat.id != null
  })
  const whiteboardLocked = payload.agent_busy
  const snapshotItems = snapshots.data?.whiteboard_snapshots || []

  async function loadSnapshot(snapshot: WhiteboardSnapshot) {
    if (whiteboardLocked || loadingSnapshotId != null) return

    setSnapshotError(null)
    setLoadingSnapshotId(snapshot.id)
    try {
      const fullSnapshot = await fetchWhiteboardSnapshot(payload.chat.id, snapshot.id)
      const snapshotScene = cloneWhiteboardScene(fullSnapshot.scene_json || { elements: [], appState: {}, files: {} })
      const current = await fetchChatWhiteboard(payload.paths.app_whiteboard_path)
      const currentScene = cloneWhiteboardScene(current.scene_json)
      const nextElements = [
        ...currentScene.elements,
        ...withFreshElementIds(snapshotScene.elements)
      ]

      if (nextElements.length > WHITEBOARD_MAX_ELEMENTS) {
        throw new ApiError(`Loading this snapshot would exceed the ${WHITEBOARD_MAX_ELEMENTS} element limit.`, { status: 422 })
      }

      if (currentScene.elements.length > 0) {
        await createWhiteboardSnapshot(payload.chat.id, {
          scene_json: currentScene,
          snapshot_kind: "auto_before_load",
          name: `Before load · ${new Date().toLocaleString()}`
        })
      }

      const mergedScene: ChatWhiteboardScene = {
        elements: nextElements,
        appState: currentScene.appState,
        files: { ...currentScene.files, ...snapshotScene.files }
      }
      const result = await patchChatWhiteboard(payload.paths.app_whiteboard_path, {
        ...mergedScene,
        expected_version: current.version
      })
      if (result.status === 409) throw new ApiError("Whiteboard changed before the snapshot could load. Try again.", { status: 409 })

      queryClient.setQueryData<ChatPayload>(queryKey, (currentPayload) => {
        if (!currentPayload) return currentPayload

        return {
          ...currentPayload,
          whiteboard: {
            version: result.payload.version,
            elements: result.payload.scene_json.elements,
            appState: result.payload.scene_json.appState,
            files: result.payload.scene_json.files
          }
        }
      })
      await queryClient.invalidateQueries({ queryKey: ["whiteboard_snapshots", String(payload.chat.id)] })
      onNotice(`Loaded ${fullSnapshot.name || "snapshot"} onto canvas`)
    } catch (error) {
      setSnapshotError(errorMessage(errorAsError(error), "Snapshot could not be loaded."))
    } finally {
      setLoadingSnapshotId(null)
    }
  }

  if (images.length === 0 && snapshotItems.length === 0 && walkthroughs.length === 0 && !snapshots.isPending && !snapshots.isError) {
    return <PanelMessage>No media shared yet.</PanelMessage>
  }

  return (
    <div className="space-y-5">
      {snapshots.isPending ? <PanelMessage>Loading snapshots...</PanelMessage> : null}
      {snapshots.isError ? <PanelMessage tone="error">{errorMessage(snapshots.error, "Unable to load snapshots.")}</PanelMessage> : null}
      {snapshotError ? <PanelMessage tone="error">{snapshotError}</PanelMessage> : null}
      {whiteboardLocked ? <div className="rounded border border-amber-200 bg-amber-50 p-3 text-sm text-amber-800 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-100">Canvas is busy. Wait for drawing to finish before loading a snapshot.</div> : null}

      {snapshotItems.length > 0 ? (
        <section className="space-y-2">
          <h2 className="text-xs font-semibold uppercase text-gray-500 dark:text-gray-400">{t("whiteboard_snapshots")}</h2>
          <div className="space-y-2">
            {snapshotItems.map((snapshot) => (
              <article className="rounded border border-gray-200 bg-white p-3 dark:border-gray-700 dark:bg-gray-950" key={snapshot.id}>
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <div className="truncate text-sm font-medium text-gray-900 dark:text-gray-100" title={snapshot.name || "Snapshot"}>{truncateSnapshotName(snapshot.name || "Snapshot")}</div>
                    <div className="mt-1 flex flex-wrap items-center gap-2 text-xs text-gray-500 dark:text-gray-400">
                      <span className="rounded bg-gray-100 px-1.5 py-0.5 font-medium text-gray-600 dark:bg-gray-800 dark:text-gray-300">{snapshotKindLabel(snapshot.snapshot_kind)}</span>
                      <span>{snapshot.element_count} {snapshot.element_count === 1 ? "element" : "elements"}</span>
                      <span>{formatRelativeTime(snapshot.created_at)}</span>
                    </div>
                  </div>
                  <button
                    className={`${secondaryButton()} shrink-0 px-2 py-1 text-xs`}
                    disabled={whiteboardLocked || loadingSnapshotId != null}
                    onClick={() => void loadSnapshot(snapshot)}
                    type="button"
                  >
                    {loadingSnapshotId === snapshot.id ? "Loading..." : "Load"}
                  </button>
                </div>
              </article>
            ))}
          </div>
        </section>
      ) : null}

      {walkthroughs.length > 0 ? (
        <section className="space-y-2">
          <h2 className="text-xs font-semibold uppercase text-gray-500 dark:text-gray-400">{t("walkthrough_media_heading")}</h2>
          <div className="space-y-2">
            {walkthroughs.map((walkthrough) => (
              <article className="rounded border border-gray-200 bg-white p-3 dark:border-gray-700 dark:bg-gray-950" key={walkthrough.id}>
                <div className="flex items-start gap-3">
                  <div aria-hidden="true" className="flex h-10 w-10 shrink-0 items-center justify-center rounded bg-gray-100 text-lg dark:bg-gray-800">🎥</div>
                  <div className="min-w-0 flex-1">
                    <div className="truncate text-sm font-medium text-gray-900 dark:text-gray-100" title={walkthrough.title}>{walkthrough.title}</div>
                    <div className="mt-1 flex flex-wrap items-center gap-2 text-xs text-gray-500 dark:text-gray-400">
                      {walkthrough.duration_seconds != null ? <span className="tabular-nums">{formatClock(walkthrough.duration_seconds)}</span> : null}
                      <span className="rounded bg-gray-100 px-1.5 py-0.5 font-medium text-gray-600 dark:bg-gray-800 dark:text-gray-300">{walkthroughStateLabel(walkthrough.state)}</span>
                      <span>{formatRelativeTime(walkthrough.created_at)}</span>
                    </div>
                    {walkthrough.state === "failed" && walkthrough.error_message ? (
                      <p className="mt-1 text-xs text-red-600 dark:text-red-400">{walkthrough.error_message}</p>
                    ) : null}
                    {!walkthrough.has_video && walkthrough.state !== "failed" ? (
                      <p className="mt-1 text-xs text-gray-400 dark:text-gray-500">{t("walkthrough_media_expired")}</p>
                    ) : null}
                  </div>
                </div>
              </article>
            ))}
          </div>
        </section>
      ) : null}

      {images.length > 0 ? (
        <section className="space-y-2">
          <h2 className="text-xs font-semibold uppercase text-gray-500 dark:text-gray-400">{t("image_attachments")}</h2>
          <div className="grid grid-cols-3 gap-2">
            {images.map(({ attachment, key }) => {
              const src = attachmentDataUrl(attachment)
              const name = attachment.name || "image attachment"

              return (
                <figure className="group/media min-w-0 space-y-1" key={key}>
                  <div className="relative aspect-square overflow-hidden rounded border border-gray-200 bg-gray-50 dark:border-gray-700 dark:bg-gray-950">
                    <button
                      aria-label={`Open ${name}`}
                      className="h-full w-full p-0 focus:outline-none focus:ring-2 focus:ring-inset focus:ring-blue-500"
                      onClick={() => setLightboxImage(attachment)}
                      title={name}
                      type="button"
                    >
                      <img alt={name} className="h-full w-full object-contain transition group-hover/media:scale-105" src={src} />
                    </button>
                    <a
                      aria-label={`Download ${name}`}
                      className="absolute right-1 top-1 rounded bg-white/90 px-2 py-1 text-xs font-medium text-gray-700 opacity-0 shadow transition hover:bg-white hover:text-gray-900 focus:opacity-100 focus:outline-none focus:ring-2 focus:ring-blue-500 group-hover/media:opacity-100 dark:bg-gray-900/90 dark:text-gray-200 dark:hover:bg-gray-900"
                      download={attachment.name || "image"}
                      href={src}
                    >
                      Download
                    </a>
                  </div>
                  <figcaption className="truncate text-xs text-gray-600 dark:text-gray-300" title={name}>{name}</figcaption>
                </figure>
              )
            })}
          </div>
        </section>
      ) : null}
      {lightboxImage ? <ImageLightbox attachment={lightboxImage} onClose={() => setLightboxImage(null)} /> : null}
    </div>
  )
}

function ChatSettingsDialog({ payload, prefix, queryKey, onClose }: { payload: ChatPayload; prefix: string; queryKey: ChatQueryKey; onClose: () => void }) {
  const queryClient = useQueryClient()
  const { t } = useT("chat")
  const providerOptions = payload.chat.chat_provider_options || []
  const configuredExplicitOptions = providerOptions.filter((option) => option.value && option.configured)
  const showProviderSelector = configuredExplicitOptions.length > 1
  const provider = useMutation({
    mutationFn: (value: string) => updateChatProvider(payload.chat.id, value || null),
    onSuccess: (updated) => {
      queryClient.setQueryData(queryKey, updated)
      updateRecentChatCache(queryClient, updated.chat)
    }
  })

  const modeOptions: Array<{ value: ChatMode; label: string }> = [
    { value: "planning", label: t("mode_planning") },
    ...(payload.coding_mode_enabled ? [{ value: "coding" as ChatMode, label: t("mode_coding") }] : []),
    ...(payload.local_mode_enabled ? [{ value: "local" as ChatMode, label: t("mode_local") }] : [])
  ]
  const mode = useMutation({
    mutationFn: (value: string) => updateChatMode(payload.chat.id, value as ChatMode || null),
    onSuccess: (updated) => {
      queryClient.setQueryData(queryKey, updated)
      updateRecentChatCache(queryClient, updated.chat)
    }
  })

  return (
    <div className="fixed inset-0 z-40 flex items-center justify-center bg-gray-950/35 p-4" role="presentation">
      <section aria-modal="true" aria-labelledby="chat-settings-title" className="w-full max-w-md rounded border border-gray-200 bg-white p-4 shadow-lg dark:border-gray-700 dark:bg-gray-900" role="dialog">
        <div className="mb-4 flex items-start justify-between gap-3">
          <div>
            <h2 className="text-base font-semibold text-gray-900 dark:text-gray-100" id="chat-settings-title">{t("chat_settings")}</h2>
            <p className="mt-1 break-words text-sm text-gray-600 dark:text-gray-300">{chatDisplayTitle(payload.chat)}</p>
          </div>
          <button aria-label={t("aria_close_settings")} className="rounded p-1 text-gray-500 hover:bg-gray-100 hover:text-gray-700 dark:text-gray-400 dark:hover:bg-gray-800 dark:hover:text-gray-200" onClick={onClose} type="button">
            <CloseIcon className="h-4 w-4" />
          </button>
        </div>
        <div className="space-y-3 text-sm">
          {showProviderSelector ? (
            <label className="block">
              <span className="mb-1 block text-xs font-medium uppercase text-gray-500 dark:text-gray-400">{t("provider")}</span>
              <select
                aria-label={t("aria_chat_provider")}
                className="w-full rounded border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500 disabled:bg-gray-100 dark:border-gray-700 dark:bg-gray-950 dark:text-gray-100 dark:disabled:bg-gray-800"
                disabled={provider.isPending}
                onChange={(event) => provider.mutate(event.target.value)}
                value={payload.chat.chat_provider || ""}
              >
                {providerOptions.map((option) => (
                  <option disabled={!option.configured} key={option.value || "default"} value={option.value || ""}>
                    {option.label}
                  </option>
                ))}
              </select>
              <span className="mt-1 block text-xs text-gray-500 dark:text-gray-400">Effective: {payload.chat.effective_chat_provider_label || "Default"}</span>
            </label>
          ) : null}
          {provider.isError ? <div className="text-xs text-red-700 dark:text-red-300">{errorMessage(provider.error, "Provider could not be updated.")}</div> : null}
          <label className="block">
            <span className="mb-1 block text-xs font-medium uppercase text-gray-500 dark:text-gray-400">{t("mode_label")}</span>
            <div className="flex rounded border border-gray-300 bg-white dark:border-gray-700 dark:bg-gray-950" role="group" aria-label={t("mode_label")}>
              {modeOptions.map(({ value, label }) => (
                <button
                  className={[
                    "flex-1 px-3 py-2 text-sm first:rounded-l last:rounded-r focus:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-terracotta-500",
                    (payload.chat.mode || "planning") === value
                      ? "bg-terracotta-600 font-medium text-white"
                      : "text-gray-700 hover:bg-gray-50 dark:text-gray-200 dark:hover:bg-gray-800",
                    mode.isPending ? "cursor-not-allowed opacity-50" : ""
                  ].join(" ")}
                  disabled={mode.isPending}
                  key={value}
                  onClick={() => mode.mutate(value)}
                  type="button"
                >
                  {label}
                </button>
              ))}
            </div>
            <span className="mt-1 block text-xs text-gray-500 dark:text-gray-400">{t("mode_hint")}</span>
          </label>
          {mode.isError ? <div className="text-xs text-red-700 dark:text-red-300">{errorMessage(mode.error, t("mode_update_error"))}</div> : null}
          {payload.chat.repository?.repository_path ? (
            <Link className="block rounded border border-gray-200 px-3 py-2 text-gray-700 hover:border-blue-200 hover:bg-blue-50 hover:text-blue-700 dark:border-gray-700 dark:text-gray-200 dark:hover:border-blue-800 dark:hover:bg-blue-950 dark:hover:text-blue-200" onClick={onClose} to={withRoutePrefix(`${payload.chat.repository.repository_path}/edit`, prefix)}>
              Repository settings
            </Link>
          ) : null}
          <Link className="block rounded border border-gray-200 px-3 py-2 text-gray-700 hover:border-blue-200 hover:bg-blue-50 hover:text-blue-700 dark:border-gray-700 dark:text-gray-200 dark:hover:border-blue-800 dark:hover:bg-blue-950 dark:hover:text-blue-200" onClick={onClose} to={withRoutePrefix("/credentials", prefix)}>
            Chat credentials
          </Link>
        </div>
      </section>
    </div>
  )
}

type WhiteboardBoundaryState = {
  failed: boolean
}

class WhiteboardBoundary extends Component<{ children: ReactNode }, WhiteboardBoundaryState> {
  state: WhiteboardBoundaryState = { failed: false }

  static getDerivedStateFromError(): WhiteboardBoundaryState {
    return { failed: true }
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    console.error("Whiteboard render failed.", error, errorInfo)
  }

  render() {
    if (this.state.failed) {
      return (
        <section>
          <div className="mb-2 text-xs font-semibold uppercase text-gray-500 dark:text-gray-400">Whiteboard</div>
          <div className="rounded border border-red-200 bg-red-50 p-3 text-sm text-red-700 dark:border-red-800 dark:bg-red-950 dark:text-red-200">
            Whiteboard unavailable.
          </div>
        </section>
      )
    }

    return this.props.children
  }
}

function WhiteboardPanel({ fullscreen, onToggleFullscreen, payload }: { fullscreen: boolean; onToggleFullscreen: () => void; payload: ChatPayload }) {
  const [Excalidraw, setExcalidraw] = useState<ExcalidrawComponent | null>(null)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [saveError, setSaveError] = useState<string | null>(null)
  const [scene, setScene] = useState<ChatWhiteboardScene>(() => whiteboardScene(payload))
  const apiRef = useRef<ExcalidrawApi | null>(null)
  const appliedSignatureRef = useRef(signatureForScene(scene))
  const chatIdRef = useRef(payload.chat.id)
  const pathRef = useRef(payload.paths.app_whiteboard_path)
  const pendingSceneRef = useRef<ChatWhiteboardScene | null>(null)
  const remoteUpdateInProgressRef = useRef(false)
  const retryingConflictRef = useRef(false)
  const saveTimerRef = useRef<number | null>(null)
  const versionRef = useRef(payload.whiteboard.version)

  const clearPendingSave = useCallback(() => {
    if (saveTimerRef.current == null) return

    window.clearTimeout(saveTimerRef.current)
    saveTimerRef.current = null
  }, [])

  const applyRemoteScene = useCallback((nextScene: ChatWhiteboardScene, nextVersion: number) => {
    remoteUpdateInProgressRef.current = true
    const copied = cloneWhiteboardScene(nextScene)
    appliedSignatureRef.current = signatureForScene(copied)
    setScene(copied)
    apiRef.current?.addFiles(asExcalidrawFiles(copied.files))
    apiRef.current?.updateScene({
      elements: asExcalidrawElements(copied.elements),
      appState: copied.appState as never
    })
    versionRef.current = nextVersion
    queueMicrotask(() => {
      remoteUpdateInProgressRef.current = false
    })
  }, [])

  const recoverConflict = useCallback(async (originalScene: ChatWhiteboardScene) => {
    if (retryingConflictRef.current) return

    retryingConflictRef.current = true
    try {
      const current = await fetchChatWhiteboard(pathRef.current)
      applyRemoteScene(current.scene_json, current.version)
      const retry = await patchChatWhiteboard(pathRef.current, {
        ...originalScene,
        expected_version: current.version
      })
      if (retry.status === 409) throw new ApiError("Whiteboard changed again before the retry completed.", { status: 409 })

      applyRemoteScene(retry.payload.scene_json, retry.payload.version)
    } finally {
      retryingConflictRef.current = false
    }
  }, [applyRemoteScene])

  const savePending = useCallback(async () => {
    const pendingScene = pendingSceneRef.current
    if (!pendingScene) return

    pendingSceneRef.current = null
    setSaveError(null)
    try {
      const result = await patchChatWhiteboard(pathRef.current, {
        ...pendingScene,
        expected_version: versionRef.current
      })
      if (result.status === 409) {
        await recoverConflict(pendingScene)
        return
      }

      applyRemoteScene(result.payload.scene_json, result.payload.version)
    } catch (error) {
      setSaveError(errorMessage(errorAsError(error), "Whiteboard save failed."))
    }
  }, [applyRemoteScene, recoverConflict])

  useEffect(() => {
    let cancelled = false
    void import("@excalidraw/excalidraw")
      .then((module) => {
        if (!cancelled) setExcalidraw(() => module.Excalidraw)
      })
      .catch((error: unknown) => {
        if (!cancelled) setLoadError(errorMessage(errorAsError(error), "Unable to load the whiteboard."))
      })

    return () => {
      cancelled = true
    }
  }, [])

  useEffect(() => {
    pathRef.current = payload.paths.app_whiteboard_path
  }, [payload.paths.app_whiteboard_path])

  useEffect(() => {
    const nextScene = whiteboardScene(payload)
    const chatChanged = chatIdRef.current !== payload.chat.id
    if (!chatChanged && payload.whiteboard.version <= versionRef.current) return

    chatIdRef.current = payload.chat.id
    applyRemoteScene(nextScene, payload.whiteboard.version)
  }, [applyRemoteScene, payload])

  useEffect(() => () => {
    clearPendingSave()
    const pendingScene = pendingSceneRef.current
    if (pendingScene) {
      void patchChatWhiteboard(pathRef.current, {
        ...pendingScene,
        expected_version: versionRef.current
      }).catch(() => {})
    }
  }, [clearPendingSave])

  const handleChange = useCallback((nextElements: readonly ChatWhiteboardElement[], nextAppState: unknown, nextFiles: unknown) => {
    if (remoteUpdateInProgressRef.current) return

    const copied = cloneWhiteboardScene({
      elements: Array.from(nextElements),
      appState: cleanWhiteboardAppState(nextAppState),
      files: cleanWhiteboardFiles(nextFiles)
    })
    const signature = signatureForScene(copied)
    if (signature === appliedSignatureRef.current) return

    appliedSignatureRef.current = signature
    setScene(copied)
    pendingSceneRef.current = copied
    clearPendingSave()
    saveTimerRef.current = window.setTimeout(() => {
      void savePending()
    }, WHITEBOARD_SAVE_DEBOUNCE_MS)
  }, [clearPendingSave, savePending])

  return (
    <section className="flex h-full min-h-0 flex-col">
      <div className="mb-2 flex items-center justify-between gap-3">
        <div className="text-xs font-semibold uppercase text-gray-500 dark:text-gray-400">Whiteboard</div>
        <div className="flex items-center gap-2">
          <button
            aria-pressed={fullscreen}
            className="rounded border border-gray-300 bg-white px-2 py-1 text-xs font-medium text-gray-700 hover:bg-gray-50 dark:border-gray-600 dark:bg-gray-900 dark:text-gray-200 dark:hover:bg-gray-800"
            onClick={onToggleFullscreen}
            type="button"
          >
            {fullscreen ? "Exit fullscreen" : "Fullscreen"}
          </button>
        </div>
      </div>
      <div className="relative min-h-0 flex-1 overflow-hidden rounded border border-gray-200 bg-gray-50 dark:border-gray-700 dark:bg-gray-950">
        {Excalidraw ? (
          <Excalidraw
            excalidrawAPI={(api) => {
              apiRef.current = api
            }}
            initialData={{
              elements: asExcalidrawElements(scene.elements),
              appState: scene.appState as never,
              files: scene.files as never
            }}
            onChange={(nextElements, nextAppState, nextFiles) => handleChange(nextElements as readonly ChatWhiteboardElement[], nextAppState, nextFiles)}
          />
        ) : (
          <div className="flex h-full items-center justify-center p-4 text-sm text-gray-500 dark:text-gray-400">
            {loadError || "Loading canvas..."}
          </div>
        )}
        {scene.elements.length === 0 ? (
          <div className="pointer-events-none absolute inset-0 flex items-center justify-center px-6 text-center text-sm text-gray-400 dark:text-gray-500">
            Empty canvas. Start sketching, or ask the agent to draw something.
          </div>
        ) : null}
      </div>
      <div className="mt-1 text-xs text-gray-500 dark:text-gray-400">
        {saveError || `${scene.elements.length} canvas ${scene.elements.length === 1 ? "element" : "elements"}`}
      </div>
    </section>
  )
}

function UsageOverlay({ payload }: { payload: ChatPayload }) {
  return (
    <p className="pointer-events-none absolute left-0 right-0 top-0 border-b border-gray-100 bg-white/95 px-4 py-1.5 text-xs text-gray-500 dark:border-gray-800 dark:bg-gray-950/95 dark:text-gray-400">
      Tokens: {formatTokenCount(payload.chat.cumulative_input_tokens)} in / {formatTokenCount(payload.chat.cumulative_output_tokens)} out · {formatCurrency(payload.chat.cumulative_cost_usd)}
    </p>
  )
}

function PanelMessage({ children, tone = "muted" }: { children: ReactNode; tone?: "muted" | "error" | "success" }) {
  const colors = {
    error: "border-red-200 bg-red-50 text-red-700 dark:border-red-800 dark:bg-red-950 dark:text-red-200",
    success: "border-green-200 bg-green-50 text-green-700 dark:border-green-800 dark:bg-green-950 dark:text-green-200",
    muted: "border-gray-200 bg-white text-gray-600 dark:border-gray-700 dark:bg-gray-900 dark:text-gray-300"
  }
  return <div className={`rounded border p-4 text-sm ${colors[tone]}`}>{children}</div>
}

function FileTreeEntry({
  node,
  openDirs,
  selectedFile,
  onToggleDir,
  onSelectFile,
  depth
}: {
  node: FileTreeNode
  openDirs: Set<string>
  selectedFile: string | null
  onToggleDir: (path: string) => void
  onSelectFile: (path: string) => void
  depth: number
}) {
  const indent = depth * 12
  if (node.type === "directory") {
    const open = openDirs.has(node.path)
    return (
      <div>
        <button
          className="flex w-full items-center gap-1 px-2 py-0.5 text-left text-xs text-gray-600 hover:bg-gray-100 dark:text-gray-400 dark:hover:bg-gray-800"
          onClick={() => onToggleDir(node.path)}
          style={{ paddingLeft: `${indent + 8}px` }}
          type="button"
        >
          <span aria-hidden="true" className="shrink-0 font-mono text-gray-400 dark:text-gray-500">{open ? "▾" : "▸"}</span>
          <span className="truncate font-medium">{node.name}</span>
        </button>
        {open ? (
          <div>
            {node.children.map((child) => (
              <FileTreeEntry
                depth={depth + 1}
                key={child.path}
                node={child}
                openDirs={openDirs}
                selectedFile={selectedFile}
                onSelectFile={onSelectFile}
                onToggleDir={onToggleDir}
              />
            ))}
          </div>
        ) : null}
      </div>
    )
  }

  const selected = selectedFile === node.path
  return (
    <button
      className={`flex w-full items-center gap-1 px-2 py-0.5 text-left text-xs ${selected ? "bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200" : "text-gray-700 hover:bg-gray-100 dark:text-gray-300 dark:hover:bg-gray-800"}`}
      onClick={() => onSelectFile(node.path)}
      style={{ paddingLeft: `${indent + 8}px` }}
      title={node.path}
      type="button"
    >
      <span className="truncate font-mono">{node.name}</span>
    </button>
  )
}

function CodingFilesPanel({ payload }: { payload: ChatPayload }) {
  const { t } = useT("chat")
  const [view, setView] = useState<"files" | "diff">("files")
  const [diffMode, setDiffMode] = useState<"cumulative" | "turn">("cumulative")
  const [selectedFile, setSelectedFile] = useState<string | null>(null)
  const [openDirs, setOpenDirs] = useState<Set<string>>(new Set())

  const filesPath = payload.paths.app_coding_files_path
  const fileContentBasePath = payload.paths.app_coding_file_path
  const diffPath = payload.paths.app_coding_diff_path
  const agentBusy = payload.agent_busy
  const refetchInterval = agentBusy ? 3000 : 15000

  const fileTree = useQuery({
    queryKey: ["coding_files", filesPath],
    queryFn: () => fetchCodingFileTree(filesPath!),
    enabled: !!filesPath,
    refetchInterval
  })

  const fileContent = useQuery({
    queryKey: ["coding_file_content", fileContentBasePath, selectedFile],
    queryFn: () => fetchCodingFileContent(fileContentBasePath!, selectedFile!),
    enabled: !!fileContentBasePath && !!selectedFile && view === "files",
    refetchInterval
  })

  const diffResult = useQuery({
    queryKey: ["coding_diff", diffPath, diffMode],
    queryFn: () => fetchCodingDiff(diffPath!, diffMode),
    enabled: !!diffPath && view === "diff",
    refetchInterval
  })

  function toggleDir(path: string) {
    setOpenDirs((prev) => {
      const next = new Set(prev)
      if (next.has(path)) next.delete(path)
      else next.add(path)
      return next
    })
  }

  const treeNodes = fileTree.data ? buildFileTree(fileTree.data.files) : []

  return (
    <div className="flex h-full min-h-0 flex-col">
      <div className="flex shrink-0 items-center gap-1 border-b border-gray-200 px-3 py-2 dark:border-gray-700">
        <button
          className={`rounded px-2 py-1 text-xs font-medium ${view === "files" ? "bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200" : "text-gray-600 hover:bg-gray-100 dark:text-gray-400 dark:hover:bg-gray-800"}`}
          onClick={() => setView("files")}
          type="button"
        >
          {t("view_files")}
        </button>
        <button
          className={`rounded px-2 py-1 text-xs font-medium ${view === "diff" ? "bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200" : "text-gray-600 hover:bg-gray-100 dark:text-gray-400 dark:hover:bg-gray-800"}`}
          onClick={() => setView("diff")}
          type="button"
        >
          {t("view_diff")}
        </button>
        {view === "diff" ? (
          <div className="ml-auto flex items-center gap-1">
            <button
              className={`rounded px-2 py-1 text-xs ${diffMode === "cumulative" ? "font-semibold text-gray-900 dark:text-gray-100" : "text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"}`}
              onClick={() => setDiffMode("cumulative")}
              type="button"
            >
              {t("diff_tab_cumulative")}
            </button>
            <span aria-hidden="true" className="text-gray-300 dark:text-gray-600">·</span>
            <button
              className={`rounded px-2 py-1 text-xs ${diffMode === "turn" ? "font-semibold text-gray-900 dark:text-gray-100" : "text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"}`}
              onClick={() => setDiffMode("turn")}
              type="button"
            >
              {t("diff_tab_turn")}
            </button>
          </div>
        ) : null}
      </div>

      {view === "files" ? (
        <div className="flex min-h-0 flex-1">
          <div className="w-48 shrink-0 overflow-y-auto border-r border-gray-200 py-1 dark:border-gray-700">
            {fileTree.isPending ? (
              <p className="px-3 py-2 text-xs text-gray-500 dark:text-gray-400">{t("files_loading")}</p>
            ) : fileTree.isError ? (
              <p className="px-3 py-2 text-xs text-red-600 dark:text-red-400">{t("files_error")}</p>
            ) : treeNodes.length === 0 ? (
              <p className="px-3 py-2 text-xs text-gray-500 dark:text-gray-400">{t("files_empty")}</p>
            ) : (
              treeNodes.map((node) => (
                <FileTreeEntry
                  depth={0}
                  key={node.path}
                  node={node}
                  openDirs={openDirs}
                  selectedFile={selectedFile}
                  onSelectFile={setSelectedFile}
                  onToggleDir={toggleDir}
                />
              ))
            )}
          </div>
          <div className="min-w-0 flex-1 overflow-y-auto">
            {!selectedFile ? (
              <p className="px-4 py-3 text-xs text-gray-500 dark:text-gray-400">{t("file_content_empty")}</p>
            ) : fileContent.isPending ? (
              <p className="px-4 py-3 text-xs text-gray-500 dark:text-gray-400">{t("file_content_loading")}</p>
            ) : fileContent.isError ? (
              <p className="px-4 py-3 text-xs text-red-600 dark:text-red-400">{t("file_content_error")}</p>
            ) : fileContent.data?.binary ? (
              <p className="px-4 py-3 text-xs text-gray-500 dark:text-gray-400">{t("file_content_binary")}</p>
            ) : fileContent.data?.too_large ? (
              <p className="px-4 py-3 text-xs text-gray-500 dark:text-gray-400">{t("file_content_too_large")}</p>
            ) : (
              <pre className="min-w-0 overflow-x-auto p-3 font-mono text-xs leading-relaxed text-gray-800 dark:text-gray-200">
                <code>{fileContent.data?.content ?? ""}</code>
              </pre>
            )}
          </div>
        </div>
      ) : (
        <div className="min-h-0 flex-1 overflow-auto">
          {diffResult.isPending ? (
            <p className="px-4 py-3 text-xs text-gray-500 dark:text-gray-400">{t("diff_loading")}</p>
          ) : diffResult.isError ? (
            <p className="px-4 py-3 text-xs text-red-600 dark:text-red-400">{t("diff_error")}</p>
          ) : !diffResult.data?.diff ? (
            <p className="px-4 py-3 text-xs text-gray-500 dark:text-gray-400">{t("diff_empty")}</p>
          ) : (
            <pre className="min-w-max font-mono text-xs leading-relaxed">
              {diffResult.data.diff.split("\n").map((line, i) => (
                <div className={`px-3 py-px ${diffLineClass(line)}`} key={i}>{line || " "}</div>
              ))}
            </pre>
          )}
        </div>
      )}
    </div>
  )
}

function routePrefix(pathname: string) {
  return pathname.startsWith("/app-shell") ? "/app-shell" : ""
}

function isPlainAnchorClick(event: ReactMouseEvent<HTMLAnchorElement>) {
  return event.button === 0 && !event.defaultPrevented && !event.metaKey && !event.altKey && !event.ctrlKey && !event.shiftKey
}

