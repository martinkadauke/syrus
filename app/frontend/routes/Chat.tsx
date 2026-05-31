import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"
import type { FormEvent, ReactNode } from "react"
import { useState } from "react"
import { useParams } from "react-router-dom"
import { ApiError } from "../api/client"
import {
  fetchChat,
  refreshChat,
  resetChat,
  sendChatMessage,
  stopChat,
  type ChatAttachmentRow,
  type ChatPayload,
  type ChatProposal,
  type ChatProposalChild,
  type ChatRenderItem,
  type ChatStructuredTool,
  type ChatSystemMessage,
  type ChatToolGroupItem
} from "../api/chats"

export function ChatRoute() {
  const params = useParams()
  const id = params.id || ""
  const chat = useQuery({
    queryKey: ["chats", id],
    queryFn: () => fetchChat(id),
    enabled: id.length > 0
  })

  return (
    <main aria-label="Chat" className="mx-auto max-w-7xl space-y-6 p-6">
      {chat.isPending ? <PanelMessage>Loading chat...</PanelMessage> : null}
      {chat.isError ? <PanelMessage tone="error">{errorMessage(chat.error, "Unable to load chat.")}</PanelMessage> : null}
      {chat.isSuccess ? <ChatView payload={chat.data} /> : null}
    </main>
  )
}

function ChatView({ payload }: { payload: ChatPayload }) {
  const queryClient = useQueryClient()
  const queryKey = ["chats", String(payload.chat.id)] as const
  const [notice, setNotice] = useState<string | null>(payload.message || null)
  const command = useMutation({
    mutationFn: (kind: "stop" | "refresh" | "reset") => {
      if (kind === "stop") return stopChat(payload.paths.app_stop_path)
      if (kind === "refresh") return refreshChat(payload.paths.app_refresh_path)
      return resetChat(payload.paths.app_reset_path)
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

      {!payload.chat_available ? (
        <section className="rounded border border-amber-200 bg-white p-6 text-sm text-amber-900">
          <div className="font-semibold">Claude credentials are required.</div>
          <p className="mt-1">Chat uses Claude. Add a Claude OAuth token in <a className="underline hover:no-underline" href={payload.paths.credentials_path}>Credentials</a> to enable chat.</p>
        </section>
      ) : (
        <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_22rem]">
          <section className="flex min-h-[34rem] min-w-0 flex-col gap-3">
            <div className="relative min-h-0 flex-1 overflow-hidden rounded border border-gray-200 bg-white">
              <MessageStream payload={payload} />
              <UsageOverlay payload={payload} />
            </div>
            <Compose payload={payload} onNotice={setNotice} />
          </section>
          <SidePanel payload={payload} />
        </div>
      )}
    </>
  )
}

function MessageStream({ payload }: { payload: ChatPayload }) {
  if (payload.messages.length === 0) {
    return (
      <div className="flex h-full min-h-[28rem] items-center justify-center p-4 text-sm text-gray-500">
        {payload.chat.repository ? "Start a chat with this repository." : "Attach a repository to start chatting."}
      </div>
    )
  }

  return (
    <div className="min-h-[28rem] space-y-4 overflow-y-auto p-4">
      {payload.has_more_older ? <div className="text-center text-xs text-gray-500">Older messages are available from the chat history endpoint.</div> : null}
      {payload.messages.map((item) => item.type === "tool_group" ? <ToolGroup item={item} key={`tool-${item.calls.map((call) => call.message_id).join("-")}`} /> : <ChatMessage item={item} key={item.id} />)}
    </div>
  )
}

function ChatMessage({ item }: { item: Extract<ChatRenderItem, { type: "message" }> }) {
  if (item.role === "user") {
    return (
      <article className="relative flex justify-end" id={`chat_message_${item.id}`}>
        <span className="absolute -top-4" id={`message-${item.id}`} />
        <div className="chat-prose chat-prose-invert max-w-[min(42rem,85%)] rounded bg-blue-600 px-4 py-2 text-white" dangerouslySetInnerHTML={{ __html: item.html }} />
      </article>
    )
  }

  if (item.role === "assistant") {
    return (
      <article className="relative" id={`chat_message_${item.id}`}>
        <span className="absolute -top-4" id={`message-${item.id}`} />
        {item.proposal ? <ProposalCard proposal={item.proposal} /> : (
          <div className="max-w-3xl rounded border border-gray-200 bg-white px-4 py-3">
            <div className="chat-prose text-gray-800" dangerouslySetInnerHTML={{ __html: item.html }} />
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

function ProposalCard({ proposal }: { proposal: ChatProposal }) {
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
      <div className="chat-prose mt-3 text-sm text-gray-800" dangerouslySetInnerHTML={{ __html: proposal.body_html }} />
      {proposal.epic_bundle ? <ProposalChildren children={proposal.children || []} /> : <ProposalMeta proposal={proposal} />}
      {proposal.proposed ? (
        <div className="mt-4 flex flex-wrap gap-2">
          <PostForm action={proposal.confirm_path}><button className={primaryButton()} type="submit">{proposal.epic_bundle ? "Confirm Epic and Jobs" : "Confirm"}</button></PostForm>
          <PostForm action={proposal.reject_path}><button className="rounded border border-red-200 px-3 py-1.5 text-sm font-medium text-red-700 hover:bg-red-50" type="submit">Reject</button></PostForm>
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

function ProposalChildren({ children }: { children: ChatProposalChild[] }) {
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
            <div className="chat-prose mt-2 text-sm text-gray-800" dangerouslySetInnerHTML={{ __html: child.body_html }} />
            {child.proposed ? <div className="mt-3"><PostForm action={child.reject_path}><button className="rounded border border-red-200 px-3 py-1.5 text-sm font-medium text-red-700 hover:bg-red-50" type="submit">Reject child Job</button></PostForm></div> : null}
          </div>
        </details>
      ))}
    </div>
  )
}

function Compose({ payload, onNotice }: { payload: ChatPayload; onNotice: (message: string | null) => void }) {
  const queryClient = useQueryClient()
  const [text, setText] = useState("")
  const queryKey = ["chats", String(payload.chat.id)] as const
  const send = useMutation({
    mutationFn: () => sendChatMessage(payload.paths.app_message_path, text),
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
        {payload.turn_in_flight ? <StopButton payload={payload} /> : null}
      </div>
    </form>
  )
}

function StopButton({ payload }: { payload: ChatPayload }) {
  const queryClient = useQueryClient()
  const stop = useMutation({
    mutationFn: () => stopChat(payload.paths.app_stop_path),
    onSuccess: (updated) => queryClient.setQueryData(["chats", String(payload.chat.id)], updated)
  })
  return (
    <button className="rounded border border-red-200 bg-white px-4 py-2 text-sm font-medium text-red-700 hover:bg-red-50 disabled:text-gray-400" disabled={Boolean(payload.chat.stop_requested_at) || stop.isPending} onClick={() => stop.mutate()} type="button">
      {payload.chat.stop_requested_at || stop.isPending ? "Stopping..." : "Stop"}
    </button>
  )
}

function SidePanel({ payload }: { payload: ChatPayload }) {
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
      <Attachments payload={payload} />
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

function Attachments({ payload }: { payload: ChatPayload }) {
  return (
    <>
      <div className="flex items-center justify-between gap-3">
        <h2 className="text-sm font-semibold text-gray-900">Attachments</h2>
        <a className="rounded bg-gray-900 px-3 py-1.5 text-xs font-medium text-white hover:bg-gray-700" href="#add-attachment">Add attachment</a>
      </div>
      <div className="space-y-4">
        <AttachmentGroup label="Repos" rows={payload.attachment_groups.repositories} />
        <AttachmentGroup label="Epics" rows={payload.attachment_groups.epics} />
        <AttachmentGroup label="Jobs" rows={payload.attachment_groups.jobs} />
        <AttachmentGroup label="Documents" rows={payload.attachment_groups.documents} />
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
      <AddAttachment payload={payload} />
    </>
  )
}

function AttachmentGroup({ label, rows }: { label: string; rows: ChatAttachmentRow[] }) {
  return (
    <section>
      <div className="mb-2 text-xs font-semibold uppercase text-gray-500">{label}</div>
      {rows.length > 0 ? (
        <div className="space-y-1">
          {rows.map((row) => (
            <PostForm action={row.detach_path} key={row.id} method="delete">
              <button className="block w-full rounded border border-gray-200 bg-gray-50 px-2 py-1.5 text-left text-xs text-gray-700 hover:border-red-200 hover:bg-red-50 hover:text-red-700" title={`Detach ${row.label}`} type="submit">{row.label}</button>
            </PostForm>
          ))}
        </div>
      ) : <div className="text-xs text-gray-400">None</div>}
    </section>
  )
}

function AddAttachment({ payload }: { payload: ChatPayload }) {
  return (
    <div className="rounded border border-gray-200 bg-gray-50 p-3" id="add-attachment">
      <h3 className="mb-3 text-sm font-semibold text-gray-900">Add attachment</h3>
      <form action={payload.chat.chat_path} className="space-y-3" method="get">
        <label className="block text-xs font-medium text-gray-600">
          Type
          <select className="mt-1 w-full rounded border border-gray-300 bg-white px-2 py-1.5 text-sm" name="attachment_type">
            <option value="Repository">Repo</option>
            <option value="Epic">Epic</option>
            <option value="Job">Job</option>
            <option value="Document">Document</option>
          </select>
        </label>
        <label className="block text-xs font-medium text-gray-600">
          Search
          <input className="mt-1 w-full rounded border border-gray-300 bg-white px-2 py-1.5 text-sm" name="attachment_query" placeholder="Search by name or id" type="search" />
        </label>
        <button className={secondaryButton()} type="submit">Search</button>
      </form>
      <div className="mt-3 space-y-1">
        {payload.attachment_results.length > 0 ? payload.attachment_results.map((record) => (
          <PostForm action={payload.paths.chat_attachments_path} key={`${record.type}-${record.id}`}>
            <input name="attachable_type" type="hidden" value={record.type} />
            <input name="attachable_id" type="hidden" value={record.id} />
            <button className="block w-full rounded border border-gray-200 bg-white px-2 py-1.5 text-left text-xs text-gray-700 hover:border-blue-200 hover:bg-blue-50 hover:text-blue-700" type="submit">{record.label}</button>
          </PostForm>
        )) : <div className="text-xs text-gray-500">No matches.</div>}
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

function PostForm({ action, method = "post", children }: { action: string; method?: "post" | "delete"; children: ReactNode }) {
  const token = document.querySelector<HTMLMetaElement>("meta[name='csrf-token']")?.content || ""
  return (
    <form action={action} className="inline" method="post">
      <input name="authenticity_token" type="hidden" value={token} />
      {method !== "post" ? <input name="_method" type="hidden" value={method} /> : null}
      {children}
    </form>
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

function errorMessage(error: Error, fallback: string) {
  return error instanceof ApiError ? error.message : fallback
}
