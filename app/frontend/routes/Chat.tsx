import { useMutation, useQuery, useQueryClient, type UseMutationResult } from "@tanstack/react-query"
import type { FormEvent, ReactNode } from "react"
import { useEffect, useState } from "react"
import { useLocation, useNavigate, useParams } from "react-router-dom"
import { ApiError } from "../api/client"
import {
  addChatAttachment,
  cancelPendingAction,
  confirmChatProposal,
  confirmPendingAction,
  createChatBookmark,
  deleteChatAttachment,
  fetchChat,
  fetchChatMessages,
  refreshChat,
  rejectChatProposal,
  resetChat,
  sendChatMessage,
  stopChat,
  type ChatAttachmentResult,
  type ChatAttachmentRow,
  type ChatPendingAction,
  type ChatPayload,
  type ChatProposal,
  type ChatProposalChild,
  type ChatRenderItem,
  type ChatStructuredTool,
  type ChatSystemMessage,
  type ChatToolGroupItem
} from "../api/chats"
import { Markdown } from "../lib/Markdown"

export function ChatRoute() {
  const params = useParams()
  const location = useLocation()
  const id = params.id || ""
  const queryKey = chatQueryKey(id, location.search)
  const chat = useQuery({
    queryKey,
    queryFn: () => fetchChat(id, location.search),
    enabled: id.length > 0
  })

  return (
    <main aria-label="Chat" className="mx-auto max-w-7xl space-y-6 p-6">
      {chat.isPending ? <PanelMessage>Loading chat...</PanelMessage> : null}
      {chat.isError ? <PanelMessage tone="error">{errorMessage(chat.error, "Unable to load chat.")}</PanelMessage> : null}
      {chat.isSuccess ? <ChatView payload={chat.data} queryKey={queryKey} /> : null}
    </main>
  )
}

type ChatQueryKey = readonly ["chats", string, string]

function chatQueryKey(id: string | number, search: string): ChatQueryKey {
  return ["chats", String(id), search] as const
}

function appendSearch(path: string, search: string) {
  return search ? `${path}${search}` : path
}

function ChatView({ payload, queryKey }: { payload: ChatPayload; queryKey: ChatQueryKey }) {
  const queryClient = useQueryClient()
  const search = queryKey[2]
  const [notice, setNotice] = useState<string | null>(payload.message || null)
  const command = useMutation({
    mutationFn: (kind: "stop" | "refresh" | "reset") => {
      if (kind === "stop") return stopChat(appendSearch(payload.paths.app_stop_path, search))
      if (kind === "refresh") return refreshChat(appendSearch(payload.paths.app_refresh_path, search))
      return resetChat(appendSearch(payload.paths.app_reset_path, search))
    },
    onSuccess: (updated) => {
      queryClient.setQueryData(queryKey, updated)
      setNotice(updated.message || null)
    }
  })

  const title = payload.chat.title || payload.chat.repository?.slug || "New chat"

  return (
    <>
      <header className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="break-words text-3xl font-semibold text-gray-900">{title}</h1>
          {payload.chat.repository ? (
            <a className="mt-1 inline-block font-mono text-sm text-blue-600 underline hover:no-underline" href={payload.chat.repository.repository_path}>{payload.chat.repository.slug}</a>
          ) : null}
        </div>
        <div className="flex flex-wrap items-center gap-2">
          {payload.chat.repository ? (
            <>
              <button className={secondaryButton()} disabled={command.isPending} onClick={() => command.mutate("refresh")} type="button">Refresh repo</button>
              <button
                className="rounded border border-red-200 bg-white px-3 py-1.5 text-sm font-medium text-red-700 hover:bg-red-50 disabled:text-gray-300"
                disabled={command.isPending}
                onClick={() => {
                  if (window.confirm("Reset this chat workspace? Any in-progress workspace state will be destroyed.")) command.mutate("reset")
                }}
                type="button"
              >
                Reset workspace
              </button>
            </>
          ) : null}
          <a className="rounded bg-gray-100 px-3 py-1.5 text-sm font-medium text-gray-700 hover:bg-gray-200" href={payload.paths.new_chat_path}>New chat</a>
        </div>
      </header>

      {notice ? <PanelMessage tone="success">{notice}</PanelMessage> : null}
      {command.isError ? <PanelMessage tone="error">{errorMessage(command.error, "Chat command failed.")}</PanelMessage> : null}
      <PendingActions payload={payload} queryKey={queryKey} onNotice={setNotice} />

      {!payload.chat_available ? (
        <section className="rounded border border-amber-200 bg-white p-6 text-sm text-amber-900">
          <div className="font-semibold">Claude credentials are required.</div>
          <p className="mt-1">Chat uses Claude. Add a Claude OAuth token in <a className="underline hover:no-underline" href={payload.paths.credentials_path}>Credentials</a> to enable chat.</p>
        </section>
      ) : (
        <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_22rem]">
          <section className="flex min-h-[34rem] min-w-0 flex-col gap-3">
            <div className="relative min-h-0 flex-1 overflow-hidden rounded border border-gray-200 bg-white">
              <MessageStream payload={payload} queryKey={queryKey} onNotice={setNotice} />
              <UsageOverlay payload={payload} />
            </div>
            <Compose payload={payload} queryKey={queryKey} onNotice={setNotice} />
          </section>
          <SidePanel payload={payload} queryKey={queryKey} onNotice={setNotice} />
        </div>
      )}
    </>
  )
}

function PendingActions({ payload, queryKey, onNotice }: { payload: ChatPayload; queryKey: ChatQueryKey; onNotice: (message: string | null) => void }) {
  const queryClient = useQueryClient()
  const search = queryKey[2]
  const action = useMutation({
    mutationFn: (input: { kind: "confirm" | "cancel"; path: string }) => {
      const path = appendSearch(input.path, search)
      return input.kind === "confirm" ? confirmPendingAction(path) : cancelPendingAction(path)
    },
    onSuccess: (updated) => {
      queryClient.setQueryData(queryKey, updated)
      onNotice(updated.message || null)
    }
  })

  if (payload.pending_actions.length === 0) return null

  return (
    <section className="space-y-3 rounded border border-amber-200 bg-amber-50 p-4">
      <h2 className="text-sm font-semibold text-amber-900">Pending actions</h2>
      {payload.pending_actions.map((pendingAction) => (
        <PendingActionRow action={pendingAction} disabled={action.isPending} key={pendingAction.id} onCancel={() => action.mutate({ kind: "cancel", path: pendingAction.app_cancel_path })} onConfirm={() => action.mutate({ kind: "confirm", path: pendingAction.app_confirm_path })} />
      ))}
      {action.isError ? <div className="text-xs text-red-700">{errorMessage(action.error, "Pending action failed.")}</div> : null}
    </section>
  )
}

function PendingActionRow({ action, disabled, onCancel, onConfirm }: { action: ChatPendingAction; disabled: boolean; onCancel: () => void; onConfirm: () => void }) {
  return (
    <div className="flex flex-wrap items-center justify-between gap-3 rounded border border-amber-200 bg-white px-3 py-2 text-sm">
      <div className="font-medium text-gray-900">{action.label}</div>
      <div className="flex gap-2">
        <button className={primaryButton()} disabled={disabled} onClick={onConfirm} type="button">Confirm</button>
        <button className={secondaryButton()} disabled={disabled} onClick={onCancel} type="button">Cancel</button>
      </div>
    </div>
  )
}

function MessageStream({ payload, queryKey, onNotice }: { payload: ChatPayload; queryKey: ChatQueryKey; onNotice: (message: string | null) => void }) {
  const [olderItems, setOlderItems] = useState<ChatRenderItem[]>([])
  const [hasMoreOlder, setHasMoreOlder] = useState(payload.has_more_older)
  const displayedItems = mergeRenderItems(olderItems, payload.messages)
  const oldestId = oldestMessageId(displayedItems)
  const loadOlder = useMutation({
    mutationFn: (before: number) => fetchChatMessages(payload.paths.app_messages_path, before),
    onSuccess: (page) => {
      setOlderItems((current) => mergeRenderItems(page.messages, current))
      setHasMoreOlder(page.has_more_older)
    }
  })

  useEffect(() => {
    setOlderItems([])
    setHasMoreOlder(payload.has_more_older)
  }, [payload.chat.id])

  useEffect(() => {
    if (olderItems.length === 0) setHasMoreOlder(payload.has_more_older)
  }, [olderItems.length, payload.has_more_older])

  if (displayedItems.length === 0) {
    return (
      <div className="flex h-full min-h-[28rem] items-center justify-center p-4 text-sm text-gray-500">
        {payload.chat.repository ? "Start a chat with this repository." : "Attach a repository to start chatting."}
      </div>
    )
  }

  return (
    <div className="min-h-[28rem] space-y-4 overflow-y-auto p-4">
      {hasMoreOlder ? (
        <div className="text-center">
          <button
            className={secondaryButton()}
            disabled={loadOlder.isPending || oldestId == null}
            onClick={() => {
              if (oldestId != null) loadOlder.mutate(oldestId)
            }}
            type="button"
          >
            {loadOlder.isPending ? "Loading..." : "Load older messages"}
          </button>
          {loadOlder.isError ? <div className="mt-2 text-xs text-red-700">{errorMessage(loadOlder.error, "Unable to load older messages.")}</div> : null}
        </div>
      ) : null}
      {displayedItems.map((item) => item.type === "tool_group" ? (
        <ToolGroup item={item} key={renderItemKey(item)} />
      ) : (
        <ChatMessage item={item} key={renderItemKey(item)} payload={payload} queryKey={queryKey} onNotice={onNotice} />
      ))}
    </div>
  )
}

function ChatMessage({ item, payload, queryKey, onNotice }: { item: Extract<ChatRenderItem, { type: "message" }>; payload: ChatPayload; queryKey: ChatQueryKey; onNotice: (message: string | null) => void }) {
  if (item.role === "user") {
    return (
      <article className="group/message relative flex justify-end pt-6" id={`chat_message_${item.id}`}>
        <span className="absolute -top-4" id={`message-${item.id}`} />
        <BookmarkControl item={item} payload={payload} queryKey={queryKey} onNotice={onNotice} />
        <Markdown className="chat-prose chat-prose-invert max-w-[min(42rem,85%)] rounded bg-blue-600 px-4 py-2 text-white" text={item.text} />
      </article>
    )
  }

  if (item.role === "assistant") {
    return (
      <article className="group/message relative pt-6" id={`chat_message_${item.id}`}>
        <span className="absolute -top-4" id={`message-${item.id}`} />
        <BookmarkControl item={item} payload={payload} queryKey={queryKey} onNotice={onNotice} />
        {item.proposal ? <ProposalCard proposal={item.proposal} queryKey={queryKey} onNotice={onNotice} /> : (
          <div className="max-w-3xl rounded border border-gray-200 bg-white px-4 py-3">
            <Markdown className="chat-prose text-gray-800" text={item.text} />
          </div>
        )}
      </article>
    )
  }

  if (item.role === "system") {
    return <SystemMessage item={item.system || { tone: "neutral", label: "System", body: item.text }} />
  }

  return <StructuredTool tool={item.tool} fallback={item.text} />
}

function BookmarkControl({ item, payload, queryKey, onNotice }: { item: Extract<ChatRenderItem, { type: "message" }>; payload: ChatPayload; queryKey: ChatQueryKey; onNotice: (message: string | null) => void }) {
  const queryClient = useQueryClient()
  const search = queryKey[2]
  const [open, setOpen] = useState(false)
  const [label, setLabel] = useState("")
  const bookmark = useMutation({
    mutationFn: () => createChatBookmark(appendSearch(payload.paths.app_bookmarks_path, search), item.id, label),
    onSuccess: (updated) => {
      queryClient.setQueryData(queryKey, updated)
      onNotice(updated.message || null)
      setLabel("")
      setOpen(false)
    }
  })

  if (!item.bookmarkable) return null

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    bookmark.mutate()
  }

  return (
    <div className={`absolute right-0 top-0 z-10 ${open ? "block" : "hidden group-hover/message:block"}`}>
      <button className="rounded border border-gray-200 bg-white px-2 py-1 text-xs font-medium text-gray-600 shadow-sm hover:bg-gray-50" onClick={() => setOpen((value) => !value)} type="button">
        Bookmark
      </button>
      {open ? (
        <form className="absolute right-0 top-8 w-64 space-y-3 rounded border border-gray-200 bg-white p-3 shadow-lg" onSubmit={submit}>
          <label className="block text-xs font-medium text-gray-600">
            Label
            <input className="mt-1 w-full rounded border border-gray-300 px-2 py-1.5 text-sm" maxLength={120} onChange={(event) => setLabel(event.target.value)} required type="text" value={label} />
          </label>
          {bookmark.isError ? <div className="text-xs text-red-700">{errorMessage(bookmark.error, "Bookmark failed.")}</div> : null}
          <div className="flex justify-end gap-2">
            <button className={secondaryButton()} disabled={bookmark.isPending} onClick={() => setOpen(false)} type="button">Cancel</button>
            <button className={primaryButton()} disabled={bookmark.isPending} type="submit">Save</button>
          </div>
        </form>
      ) : null}
    </div>
  )
}

function ToolGroup({ item }: { item: ChatToolGroupItem }) {
  const details = item.calls.map((call) => call.detail).filter(Boolean).join(", ")
  return (
    <details className="group/tool">
      <summary className="flex min-w-0 cursor-pointer items-baseline gap-2 py-0.5 text-sm text-gray-700 hover:text-gray-900">
        <span className="text-gray-400 group-open/tool:rotate-90">▸</span>
        <span className="font-mono font-medium text-gray-900">{item.tool}</span>
        <span className="min-w-0 flex-1 truncate font-mono text-gray-600">{details}</span>
        {item.calls.length > 1 ? <span className="ml-auto rounded-full bg-gray-100 px-2 py-0.5 text-xs text-gray-500">{item.calls.length}</span> : null}
      </summary>
      <div className="ml-5 mt-1 space-y-2 border-l border-gray-200 pl-3 text-xs">
        {item.calls.map((call) => (
          <div key={call.message_id}>
            <div className="break-words font-mono text-gray-700">{item.tool}{call.detail ? `(${call.detail})` : ""}</div>
            {call.result_body ? <pre className={`mt-1 whitespace-pre-wrap break-words font-mono text-gray-600 ${call.result_error ? "text-red-600" : ""}`}>{call.result_body}</pre> : null}
          </div>
        ))}
      </div>
    </details>
  )
}

function StructuredTool({ tool, fallback }: { tool?: ChatStructuredTool; fallback: string }) {
  const name = tool?.name || "tool"
  return (
    <details className="text-xs open:rounded open:border open:border-gray-200 open:bg-gray-50">
      <summary className="flex cursor-pointer items-baseline gap-2 py-0.5 text-sm text-gray-700 hover:text-gray-900 group-open/tool:px-3 group-open/tool:py-2">
        <span className="text-gray-400">▸</span>
        <span className="font-mono font-medium text-gray-900">{name}</span>
        {tool?.proposal_id ? <span className="text-gray-600">Proposal #{tool.proposal_id} {tool.proposal_state_label ? `created (${tool.proposal_state_label})` : ""}</span> : null}
      </summary>
      <pre className="overflow-x-auto px-3 pb-3 font-mono text-gray-700 whitespace-pre-wrap break-words">{JSON.stringify(tool?.payload || fallback, null, 2)}</pre>
    </details>
  )
}

function SystemMessage({ item }: { item: ChatSystemMessage }) {
  const colors = {
    success: "border-emerald-200 bg-emerald-50 text-emerald-900",
    warning: "border-amber-200 bg-amber-50 text-amber-900",
    error: "border-red-200 bg-red-50 text-red-900",
    neutral: "border-gray-200 bg-gray-50 text-gray-600"
  }
  return (
    <div className="flex justify-center">
      <div className={`inline-flex max-w-full items-center gap-2 rounded-full border px-3 py-1 text-xs ${colors[item.tone]}`}>
        <span className="shrink-0 rounded bg-white/70 px-1.5 py-0.5 font-medium uppercase tracking-wide">{item.label}</span>
        <span className="min-w-0 break-words">{item.body}</span>
      </div>
    </div>
  )
}

function ProposalCard({ proposal, queryKey, onNotice }: { proposal: ChatProposal; queryKey: ChatQueryKey; onNotice: (message: string | null) => void }) {
  const queryClient = useQueryClient()
  const search = queryKey[2]
  const proposalAction = useMutation({
    mutationFn: (input: { action: "confirm" | "reject"; path: string }) => {
      const path = appendSearch(input.path, search)
      return input.action === "confirm" ? confirmChatProposal(path) : rejectChatProposal(path)
    },
    onSuccess: (updated) => {
      queryClient.setQueryData(queryKey, updated)
      onNotice(updated.message || null)
    }
  })

  if (proposal.materialized_label && proposal.materialized_path) {
    return (
      <div className="flex items-center gap-2">
        <span className="text-sm text-gray-500">Confirmed proposal</span>
        <a className="inline-flex items-center rounded-full border border-blue-200 bg-blue-50 px-3 py-1 text-sm font-medium text-blue-700 hover:bg-blue-100" href={proposal.materialized_path}>{proposal.materialized_label}</a>
      </div>
    )
  }

  return (
    <article className={`max-w-4xl rounded border bg-white px-4 py-3 ${proposal.resolved ? "border-gray-200 opacity-70 grayscale" : "border-blue-200"}`}>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <h3 className="text-base font-semibold text-gray-900">{proposal.title}</h3>
            <span className="rounded bg-indigo-50 px-2 py-0.5 text-xs font-medium text-indigo-700">{proposal.epic_bundle ? "Epic" : proposal.kind_label}</span>
            <span className={`rounded px-2 py-0.5 text-xs font-medium ${proposal.proposed ? "bg-blue-50 text-blue-700" : "bg-gray-100 text-gray-600"}`}>{proposal.state_label}</span>
            {proposal.epic_bundle ? <span className="rounded bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-600">{proposal.active_children_count || 0} child Jobs</span> : null}
          </div>
          <p className="mt-1 font-mono text-xs text-gray-500">{proposal.slug}</p>
        </div>
      </div>
      <Markdown className="chat-prose mt-3 text-sm text-gray-800" text={proposal.body} />
      {proposal.epic_bundle ? <ProposalChildren children={proposal.children || []} mutation={proposalAction} /> : <ProposalMeta proposal={proposal} />}
      {proposal.proposed ? (
        <div className="mt-4 flex flex-wrap gap-2">
          <button
            className={primaryButton()}
            disabled={proposalAction.isPending}
            onClick={() => proposalAction.mutate({ action: "confirm", path: proposal.app_confirm_path })}
            type="button"
          >
            {proposal.epic_bundle ? "Confirm Epic and Jobs" : "Confirm"}
          </button>
          <button
            className="rounded border border-red-200 px-3 py-1.5 text-sm font-medium text-red-700 hover:bg-red-50 disabled:text-gray-300"
            disabled={proposalAction.isPending}
            onClick={() => proposalAction.mutate({ action: "reject", path: proposal.app_reject_path })}
            type="button"
          >
            Reject
          </button>
          {proposalAction.isError ? <div className="basis-full text-xs text-red-700">{errorMessage(proposalAction.error, "Proposal command failed.")}</div> : null}
        </div>
      ) : null}
    </article>
  )
}

function ProposalMeta({ proposal }: { proposal: ChatProposal }) {
  return (
    <dl className="mt-3 grid gap-2 text-xs text-gray-600 sm:grid-cols-2">
      <div><dt className="font-medium text-gray-500">Attached scope</dt><dd>{proposal.scoped_repository_slug || "No repository attached"}</dd></div>
      <div>
        <dt className="font-medium text-gray-500">Dependencies</dt>
        <dd>{proposal.dependencies.length > 0 ? <PillList values={proposal.dependencies} /> : "None"}</dd>
      </div>
      {proposal.target_epic_label ? <div><dt className="font-medium text-gray-500">Target Epic</dt><dd>{proposal.target_epic_label}</dd></div> : null}
    </dl>
  )
}

function ProposalChildren({ children, mutation }: { children: ChatProposalChild[]; mutation: UseMutationResult<ChatPayload, Error, { action: "confirm" | "reject"; path: string }> }) {
  if (children.length === 0) return null
  return (
    <div className="mt-4 divide-y divide-gray-100 rounded border border-gray-200">
      {children.map((child) => (
        <details className="group" key={child.id}>
          <summary className="flex cursor-pointer items-center gap-3 px-3 py-2 text-sm hover:bg-gray-50">
            <span className="text-gray-400 group-open:rotate-90">▸</span>
            <span className="min-w-0 flex-1 truncate font-medium text-gray-900">{child.title}</span>
            {child.dependencies.length > 0 ? <span className="shrink-0 rounded bg-gray-100 px-2 py-0.5 font-mono text-xs text-gray-600">depends on {child.dependencies.join(", ")}</span> : null}
            <span className={`shrink-0 rounded px-2 py-0.5 text-xs font-medium ${child.proposed ? "bg-blue-50 text-blue-700" : "bg-gray-100 text-gray-600"}`}>{child.state_label}</span>
          </summary>
          <div className="border-t border-gray-100 px-8 py-3 text-sm text-gray-700">
            <div className="flex flex-wrap items-center gap-2 text-xs text-gray-500"><span className="font-mono">{child.slug}</span><span>{child.repository_slug || "No repository attached"}</span></div>
            <Markdown className="chat-prose mt-2 text-sm text-gray-800" text={child.body} />
            {child.proposed ? (
              <div className="mt-3">
                <button
                  className="rounded border border-red-200 px-3 py-1.5 text-sm font-medium text-red-700 hover:bg-red-50 disabled:text-gray-300"
                  disabled={mutation.isPending}
                  onClick={() => mutation.mutate({ action: "reject", path: child.app_reject_path })}
                  type="button"
                >
                  Reject child Job
                </button>
              </div>
            ) : null}
          </div>
        </details>
      ))}
    </div>
  )
}

function Compose({ payload, queryKey, onNotice }: { payload: ChatPayload; queryKey: ChatQueryKey; onNotice: (message: string | null) => void }) {
  const queryClient = useQueryClient()
  const [text, setText] = useState("")
  const search = queryKey[2]
  const send = useMutation({
    mutationFn: () => sendChatMessage(appendSearch(payload.paths.app_message_path, search), text),
    onSuccess: (updated) => {
      queryClient.setQueryData(queryKey, updated)
      setText("")
      onNotice(updated.message || null)
    }
  })

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    onNotice(null)
    send.mutate()
  }

  return (
    <form className="rounded border border-gray-200 bg-white p-3" onSubmit={submit}>
      {send.isError ? <div className="mb-2 text-sm text-red-700">{errorMessage(send.error, "Message failed.")}</div> : null}
      <div className="flex items-end gap-3">
        <textarea
          className="min-h-9 max-h-24 flex-1 resize-none overflow-y-auto rounded border border-gray-300 px-3 py-2 text-sm leading-5 focus:border-blue-500 focus:ring-blue-500 disabled:bg-gray-50"
          disabled={payload.turn_in_flight || send.isPending}
          onChange={(event) => setText(event.target.value)}
          placeholder={payload.chat.repository ? "Ask about this repository..." : "Attach a repository to start chatting..."}
          required
          rows={1}
          value={text}
        />
        <button className={primaryButton()} disabled={payload.turn_in_flight || send.isPending} type="submit">Send</button>
        {payload.turn_in_flight ? <StopButton payload={payload} queryKey={queryKey} /> : null}
      </div>
    </form>
  )
}

function StopButton({ payload, queryKey }: { payload: ChatPayload; queryKey: ChatQueryKey }) {
  const queryClient = useQueryClient()
  const search = queryKey[2]
  const stop = useMutation({
    mutationFn: () => stopChat(appendSearch(payload.paths.app_stop_path, search)),
    onSuccess: (updated) => queryClient.setQueryData(queryKey, updated)
  })
  return (
    <button className="rounded border border-red-200 bg-white px-4 py-2 text-sm font-medium text-red-700 hover:bg-red-50 disabled:text-gray-400" disabled={Boolean(payload.chat.stop_requested_at) || stop.isPending} onClick={() => stop.mutate()} type="button">
      {payload.chat.stop_requested_at || stop.isPending ? "Stopping..." : "Stop"}
    </button>
  )
}

function SidePanel({ payload, queryKey, onNotice }: { payload: ChatPayload; queryKey: ChatQueryKey; onNotice: (message: string | null) => void }) {
  return (
    <aside aria-label="Chat side panel" className="space-y-4 rounded border border-gray-200 bg-white p-4">
      <section>
        <div className="mb-2 text-xs font-semibold uppercase text-gray-500">Whiteboard</div>
        <div className="rounded border border-gray-200 bg-gray-50 p-3 text-xs text-gray-600">
          <div>Version {payload.whiteboard.version}</div>
          <div>{payload.whiteboard.elements.length} canvas {payload.whiteboard.elements.length === 1 ? "element" : "elements"}</div>
        </div>
      </section>
      <Bookmarks payload={payload} />
      <Attachments payload={payload} queryKey={queryKey} onNotice={onNotice} />
    </aside>
  )
}

function Bookmarks({ payload }: { payload: ChatPayload }) {
  return (
    <section>
      <div className="mb-2 text-xs font-semibold uppercase text-gray-500">Bookmarks</div>
      {payload.bookmarks.length > 0 ? (
        <nav aria-label="Chat bookmarks" className="space-y-1">
          {payload.bookmarks.map((bookmark) => (
            <a className="block rounded border border-gray-200 bg-gray-50 px-2 py-1.5 text-xs text-gray-700 hover:border-blue-200 hover:bg-blue-50 hover:text-blue-700" href={`#message-${bookmark.chat_message_id}`} key={bookmark.id}>
              <span className="block truncate">{bookmark.label}</span>
            </a>
          ))}
        </nav>
      ) : <div className="text-xs text-gray-400">None</div>}
    </section>
  )
}

function Attachments({ payload, queryKey, onNotice }: { payload: ChatPayload; queryKey: ChatQueryKey; onNotice: (message: string | null) => void }) {
  return (
    <>
      <div className="flex items-center justify-between gap-3">
        <h2 className="text-sm font-semibold text-gray-900">Attachments</h2>
        <a className="rounded bg-gray-900 px-3 py-1.5 text-xs font-medium text-white hover:bg-gray-700" href="#add-attachment">Add attachment</a>
      </div>
      <div className="space-y-4">
        <AttachmentGroup label="Repos" rows={payload.attachment_groups.repositories} queryKey={queryKey} onNotice={onNotice} />
        <AttachmentGroup label="Epics" rows={payload.attachment_groups.epics} queryKey={queryKey} onNotice={onNotice} />
        <AttachmentGroup label="Jobs" rows={payload.attachment_groups.jobs} queryKey={queryKey} onNotice={onNotice} />
        <AttachmentGroup label="Documents" rows={payload.attachment_groups.documents} queryKey={queryKey} onNotice={onNotice} />
      </div>
      <section>
        <div className="mb-2 text-xs font-semibold uppercase text-gray-500">In-scope documents</div>
        {payload.documents_in_scope.length > 0 ? (
          <div className="space-y-1">
            {payload.documents_in_scope.map((document) => (
              <div className="rounded border border-gray-200 px-2 py-1.5 text-xs" key={document.id}>
                <div className="font-medium text-gray-800">{document.title}</div>
                <div className="font-mono text-[0.7rem] text-gray-500">{document.repository_slug}</div>
              </div>
            ))}
          </div>
        ) : <div className="text-xs text-gray-400">No documents in scope.</div>}
      </section>
      <AddAttachment payload={payload} queryKey={queryKey} onNotice={onNotice} />
    </>
  )
}

function AttachmentGroup({ label, rows, queryKey, onNotice }: { label: string; rows: ChatAttachmentRow[]; queryKey: ChatQueryKey; onNotice: (message: string | null) => void }) {
  const queryClient = useQueryClient()
  const search = queryKey[2]
  const detach = useMutation({
    mutationFn: (path: string) => deleteChatAttachment(appendSearch(path, search)),
    onSuccess: (updated) => {
      queryClient.setQueryData(queryKey, updated)
      onNotice(updated.message || null)
    }
  })

  return (
    <section>
      <div className="mb-2 text-xs font-semibold uppercase text-gray-500">{label}</div>
      {rows.length > 0 ? (
        <div className="space-y-1">
          {rows.map((row) => (
            <button
              className="block w-full rounded border border-gray-200 bg-gray-50 px-2 py-1.5 text-left text-xs text-gray-700 hover:border-red-200 hover:bg-red-50 hover:text-red-700 disabled:text-gray-300"
              disabled={detach.isPending}
              key={row.id}
              onClick={() => detach.mutate(row.app_detach_path)}
              title={`Detach ${row.label}`}
              type="button"
            >
              {row.label}
            </button>
          ))}
        </div>
      ) : <div className="text-xs text-gray-400">None</div>}
      {detach.isError ? <div className="mt-1 text-xs text-red-700">{errorMessage(detach.error, "Detach failed.")}</div> : null}
    </section>
  )
}

function AddAttachment({ payload, queryKey, onNotice }: { payload: ChatPayload; queryKey: ChatQueryKey; onNotice: (message: string | null) => void }) {
  const queryClient = useQueryClient()
  const location = useLocation()
  const navigate = useNavigate()
  const params = new URLSearchParams(location.search)
  const [type, setType] = useState(params.get("attachment_type") || "Repository")
  const [query, setQuery] = useState(params.get("attachment_query") || "")
  const add = useMutation({
    mutationFn: (record: ChatAttachmentResult) => addChatAttachment(appendSearch(payload.paths.app_attachments_path, location.search), record),
    onSuccess: (updated) => {
      queryClient.setQueryData(queryKey, updated)
      onNotice(updated.message || null)
    }
  })

  useEffect(() => {
    const next = new URLSearchParams(location.search)
    setType(next.get("attachment_type") || "Repository")
    setQuery(next.get("attachment_query") || "")
  }, [location.search])

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const next = new URLSearchParams()
    next.set("attachment_type", type)
    if (query.trim()) next.set("attachment_query", query.trim())
    navigate(`${payload.chat.chat_path}?${next.toString()}`)
  }

  return (
    <div className="rounded border border-gray-200 bg-gray-50 p-3" id="add-attachment">
      <h3 className="mb-3 text-sm font-semibold text-gray-900">Add attachment</h3>
      <form className="space-y-3" onSubmit={submit}>
        <label className="block text-xs font-medium text-gray-600">
          Type
          <select className="mt-1 w-full rounded border border-gray-300 bg-white px-2 py-1.5 text-sm" name="attachment_type" onChange={(event) => setType(event.target.value)} value={type}>
            <option value="Repository">Repo</option>
            <option value="Epic">Epic</option>
            <option value="Job">Job</option>
            <option value="Document">Document</option>
          </select>
        </label>
        <label className="block text-xs font-medium text-gray-600">
          Search
          <input className="mt-1 w-full rounded border border-gray-300 bg-white px-2 py-1.5 text-sm" name="attachment_query" onChange={(event) => setQuery(event.target.value)} placeholder="Search by name or id" type="search" value={query} />
        </label>
        <button className={secondaryButton()} type="submit">Search</button>
      </form>
      <div className="mt-3 space-y-1">
        {payload.attachment_results.length > 0 ? payload.attachment_results.map((record) => (
          <button
            className="block w-full rounded border border-gray-200 bg-white px-2 py-1.5 text-left text-xs text-gray-700 hover:border-blue-200 hover:bg-blue-50 hover:text-blue-700 disabled:text-gray-300"
            disabled={add.isPending}
            key={`${record.type}-${record.id}`}
            onClick={() => add.mutate(record)}
            type="button"
          >
            {record.label}
          </button>
        )) : <div className="text-xs text-gray-500">No matches.</div>}
        {add.isError ? <div className="text-xs text-red-700">{errorMessage(add.error, "Attachment failed.")}</div> : null}
      </div>
    </div>
  )
}

function UsageOverlay({ payload }: { payload: ChatPayload }) {
  return (
    <p className="pointer-events-none absolute left-0 right-0 top-0 border-b border-gray-100 bg-white/95 px-4 py-1.5 text-xs text-gray-500">
      Tokens: {formatThousands(payload.chat.cumulative_input_tokens)}k in / {formatThousands(payload.chat.cumulative_output_tokens)}k out · {formatCurrency(payload.chat.cumulative_cost_usd)}
    </p>
  )
}

function PillList({ values }: { values: string[] }) {
  return <div className="flex flex-wrap gap-1">{values.map((value) => <span className="rounded bg-gray-100 px-2 py-0.5 font-mono" key={value}>{value}</span>)}</div>
}

function PanelMessage({ children, tone = "muted" }: { children: ReactNode; tone?: "muted" | "error" | "success" }) {
  const colors = {
    error: "border-red-200 bg-red-50 text-red-700",
    success: "border-green-200 bg-green-50 text-green-700",
    muted: "border-gray-200 bg-white text-gray-600"
  }
  return <div className={`rounded border p-4 text-sm ${colors[tone]}`}>{children}</div>
}

function primaryButton() {
  return "rounded bg-blue-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-blue-500 disabled:cursor-not-allowed disabled:bg-gray-300"
}

function secondaryButton() {
  return "rounded border border-gray-300 bg-white px-3 py-1.5 text-sm font-medium text-gray-700 hover:bg-gray-50 disabled:text-gray-300"
}

function formatThousands(value: number) {
  const thousands = value / 1000
  return Number.isInteger(thousands) ? String(thousands) : thousands.toFixed(1).replace(/\.0$/, "")
}

function formatCurrency(value: number) {
  return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", minimumFractionDigits: 4, maximumFractionDigits: 4 }).format(value)
}

function mergeRenderItems(...groups: ChatRenderItem[][]) {
  const seen = new Set<string>()
  const items: ChatRenderItem[] = []

  for (const item of groups.flat()) {
    const key = renderItemKey(item)
    if (seen.has(key)) continue

    seen.add(key)
    items.push(item)
  }

  return items
}

function renderItemKey(item: ChatRenderItem) {
  if (item.type === "message") return `message-${item.id}`

  return `tool-${item.calls.map((call) => call.message_id).join("-")}`
}

function oldestMessageId(items: ChatRenderItem[]) {
  const ids = items.flatMap((item) => item.type === "message" ? [item.id] : item.calls.map((call) => call.message_id))
  return ids.length > 0 ? Math.min(...ids) : null
}

function errorMessage(error: Error, fallback: string) {
  return error instanceof ApiError ? error.message : fallback
}
