import { useMutation, useQueryClient } from "@tanstack/react-query"
import { useEffect, useRef, useState } from "react"
import { useLocation, useNavigate } from "react-router-dom"
import "@excalidraw/excalidraw/index.css"
import { addChatAttachment, deleteChatAttachment, type ChatAttachmentResult, type ChatAttachmentRow, type ChatPayload } from "../../api/chats"
import { useT } from "../../hooks/useT"
import { errorMessage } from "../../lib/errorMessage"
import { type ChatQueryKey } from "./constants"
import { appendSearch, withRoutePrefix } from "./utils"




// Attachment UI extracted from Chat.tsx: the workspace attachment list
// (Attachments + AttachmentGroup) and the AddAttachment picker/popover.
// Attachments is rendered by the workspace context tab and the composer;
// AddAttachment by the composer. Depends only on leaf modules and shared UI
// imports; unused header imports were pruned after the move.

export function Attachments({ payload, queryKey, onNotice }: { payload: ChatPayload; prefix: string; queryKey: ChatQueryKey; onNotice: (message: string | null) => void }) {
  const { t } = useT("chat")
  return (
    <>
      <div className="flex items-center justify-between gap-3">
        <h2 className="text-sm font-semibold text-gray-900 dark:text-gray-100">{t("attachments")}</h2>
      </div>
      <div className="space-y-4">
        <AttachmentGroup label="Repos" rows={payload.attachment_groups.repositories} queryKey={queryKey} onNotice={onNotice} />
        <AttachmentGroup label="Epics" rows={payload.attachment_groups.epics} queryKey={queryKey} onNotice={onNotice} />
        <AttachmentGroup label="Jobs" rows={payload.attachment_groups.jobs} queryKey={queryKey} onNotice={onNotice} />
        <AttachmentGroup label="Documents" rows={payload.attachment_groups.documents} queryKey={queryKey} onNotice={onNotice} />
      </div>
      <section>
        <div className="mb-2 text-xs font-semibold uppercase text-gray-500 dark:text-gray-400">In-scope documents</div>
        {(payload.documents_in_scope ?? []).length > 0 ? (
          <div className="space-y-1">
            {(payload.documents_in_scope ?? []).map((document) => (
              <div className="rounded border border-gray-200 px-2 py-1.5 text-xs dark:border-gray-700" key={document.id}>
                <div className="font-medium text-gray-800 dark:text-gray-100">{document.title}</div>
                <div className="font-mono text-[0.7rem] text-gray-500 dark:text-gray-400">{document.repository_slug}</div>
              </div>
            ))}
          </div>
        ) : <div className="text-xs text-gray-400 dark:text-gray-500">No documents in scope.</div>}
      </section>
    </>
  )
}

function AttachmentGroup({ label, rows, queryKey, onNotice }: { label: string; rows: ChatAttachmentRow[]; queryKey: ChatQueryKey; onNotice: (message: string | null) => void }) {
  const queryClient = useQueryClient()
  const search = queryKey[2]
  const [pendingDetachId, setPendingDetachId] = useState<string | null>(null)
  const detach = useMutation({
    mutationFn: (path: string) => deleteChatAttachment(appendSearch(path, search)),
    onSuccess: (updated) => {
      queryClient.setQueryData(queryKey, updated)
      onNotice(updated.message || null)
    }
  })

  return (
    <section>
      <div className="mb-2 text-xs font-semibold uppercase text-gray-500 dark:text-gray-400">{label}</div>
      {(rows ?? []).length > 0 ? (
        <div className="space-y-1">
          {(rows ?? []).map((row) => {
            const rowId = String(row.id)
            const pending = pendingDetachId === rowId
            return (
              <div className="flex items-center gap-2" key={row.id}>
                <button
                  className={`block w-full rounded border px-2 py-1.5 text-left text-xs disabled:text-gray-300 dark:disabled:text-gray-600 ${pending ? "border-red-200 bg-red-50 text-red-700 dark:border-red-800 dark:bg-red-950 dark:text-red-300" : "border-gray-200 bg-gray-50 text-gray-700 hover:border-red-200 hover:bg-red-50 hover:text-red-700 dark:border-gray-700 dark:bg-gray-800 dark:text-gray-300 dark:hover:border-red-800 dark:hover:bg-red-950 dark:hover:text-red-300"}`}
                  disabled={detach.isPending}
                  onClick={() => {
                    if (pending) {
                      setPendingDetachId(null)
                      detach.mutate(row.app_detach_path)
                    } else {
                      setPendingDetachId(rowId)
                    }
                  }}
                  title={`Detach ${row.label}`}
                  type="button"
                >
                  {pending ? `Detach ${row.label}?` : row.label}
                </button>
                {pending ? (
                  <button
                    className="shrink-0 rounded border border-gray-300 bg-white px-2 py-1 text-xs font-medium text-gray-600 hover:bg-gray-50 disabled:text-gray-300 dark:border-gray-600 dark:bg-gray-900 dark:text-gray-300 dark:hover:bg-gray-800 dark:disabled:text-gray-600"
                    disabled={detach.isPending}
                    onClick={() => setPendingDetachId(null)}
                    type="button"
                  >
                    Cancel
                  </button>
                ) : null}
              </div>
            )
          })}
        </div>
      ) : <div className="text-xs text-gray-400 dark:text-gray-500">None</div>}
      {detach.isError ? <div className="mt-1 text-xs text-red-700 dark:text-red-300">{errorMessage(detach.error, "Detach failed.")}</div> : null}
    </section>
  )
}

export function AddAttachment({ payload, prefix, queryKey, onAttached, onNotice }: { payload: ChatPayload; prefix: string; queryKey: ChatQueryKey; onAttached?: () => void; onNotice: (message: string | null) => void }) {
  const { t } = useT("chat")
  const queryClient = useQueryClient()
  const location = useLocation()
  const navigate = useNavigate()
  const params = new URLSearchParams(location.search)
  const [type, setType] = useState(params.get("attachment_type") || "Repository")
  const [query, setQuery] = useState(params.get("attachment_query") || "")
  const searchInputRef = useRef<HTMLInputElement | null>(null)
  const submitTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const add = useMutation({
    mutationFn: (record: ChatAttachmentResult) => addChatAttachment(appendSearch(payload.paths.app_attachments_path, location.search), record),
    onSuccess: (updated) => {
      queryClient.setQueryData(queryKey, updated)
      onNotice(updated.message || null)
      onAttached?.()
    }
  })

  useEffect(() => {
    const next = new URLSearchParams(location.search)
    setType(next.get("attachment_type") || "Repository")
    setQuery(next.get("attachment_query") || "")
  }, [location.search])

  useEffect(() => {
    return () => {
      if (submitTimer.current) clearTimeout(submitTimer.current)
    }
  }, [])

  useEffect(() => {
    searchInputRef.current?.focus()
  }, [])

  function submitSearch() {
    navigateToSearch(type, query)
  }

  function scheduleSubmit(nextQuery: string) {
    if (submitTimer.current) clearTimeout(submitTimer.current)
    submitTimer.current = setTimeout(() => {
      navigateToSearch(type, nextQuery)
    }, 200)
  }

  function submitWithType(nextType: string) {
    if (submitTimer.current) clearTimeout(submitTimer.current)
    navigateToSearch(nextType, query)
  }

  function navigateToSearch(nextType: string, nextQuery: string) {
    const next = new URLSearchParams()
    next.set("attachment_type", nextType)
    if (nextQuery.trim()) next.set("attachment_query", nextQuery.trim())
    navigate(withRoutePrefix(`${payload.chat.chat_path}?${next.toString()}`, prefix))
  }

  return (
    <div>
      <div>
        <div className="flex gap-1 p-2">
          {(["Repository", "Epic", "Job", "Document"] as const).map((nextType) => (
            <button
              className={`rounded px-2 py-1 text-xs font-medium transition-colors ${
                type === nextType
                  ? "bg-blue-600 text-white dark:bg-blue-500"
                  : "text-gray-600 hover:bg-gray-100 dark:text-gray-400 dark:hover:bg-gray-800"
              }`}
              key={nextType}
              onClick={() => {
                setType(nextType)
                submitWithType(nextType)
              }}
              type="button"
            >
              {nextType === "Repository" ? "Repo" : nextType === "Document" ? "Doc" : nextType}
            </button>
          ))}
        </div>
        <div className="px-2 pb-2">
          <input
            autoFocus
            className="w-full rounded border border-gray-200 bg-white px-2 py-1.5 text-sm placeholder:text-gray-400 focus:border-blue-500 focus:outline-none dark:border-gray-700 dark:bg-gray-950 dark:text-gray-100 dark:placeholder:text-gray-500"
            data-autofocus
            name="attachment_query"
            onChange={(event) => {
              setQuery(event.target.value)
              scheduleSubmit(event.target.value)
            }}
            onKeyDown={(event) => {
              if (event.key === "Enter") {
                event.preventDefault()
                submitSearch()
              }
            }}
            placeholder={t("ph_search_name_id")}
            ref={searchInputRef}
            type="search"
            value={query}
          />
        </div>
      </div>
      <div className="space-y-0 border-t border-gray-100 dark:border-gray-800">
        {(payload.attachment_results ?? []).length > 0 ? (payload.attachment_results ?? []).map((record) => (
          <button
            className="block w-full px-3 py-1.5 text-left text-sm text-gray-700 hover:bg-blue-50 hover:text-blue-700 disabled:text-gray-300 dark:text-gray-300 dark:hover:bg-blue-950 dark:hover:text-blue-200 dark:disabled:text-gray-600"
            disabled={add.isPending}
            key={`${record.type}-${record.id}`}
            onClick={() => add.mutate(record)}
            type="button"
          >
            {record.label}
          </button>
        )) : <div className="px-3 py-2 text-xs text-gray-500 dark:text-gray-400">No matches.</div>}
        {add.isError ? <div className="text-xs text-red-700 dark:text-red-300">{errorMessage(add.error, "Attachment failed.")}</div> : null}
      </div>
    </div>
  )
}
