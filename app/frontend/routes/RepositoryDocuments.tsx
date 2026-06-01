import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"
import type { FormEvent, ReactNode } from "react"
import { useState } from "react"
import { Link, useLocation, useParams } from "react-router-dom"
import { ApiError } from "../api/client"
import { NoticeToast } from "../components/NoticeToast"
import {
  createRepositoryDocument,
  deleteRepositoryDocument,
  fetchRepositoryDocuments,
  type RepositoryDocument,
  type RepositoryDocumentInput,
  type RepositoryDocumentsPayload
} from "../api/repositoryDocuments"
import { RepositoryTabs } from "../components/RepositoryTabs"

export function RepositoryDocumentsRoute() {
  const location = useLocation()
  const params = useParams()
  const repositoryId = params.repositoryId || ""
  const documents = useQuery({
    queryKey: ["repositories", repositoryId, "documents"],
    queryFn: () => fetchRepositoryDocuments(repositoryId),
    enabled: repositoryId.length > 0
  })

  return (
    <main aria-label="Repository documents" className="mx-auto max-w-[96rem] space-y-6 p-6">
      {documents.isPending ? <PanelMessage>Loading repository documents...</PanelMessage> : null}
      {documents.isError ? <RepositoryDocumentsError error={documents.error} /> : null}
      {documents.isSuccess ? <RepositoryDocumentsView payload={documents.data} prefix={routePrefix(location.pathname)} /> : null}
    </main>
  )
}

function RepositoryDocumentsView({ payload, prefix }: { payload: RepositoryDocumentsPayload; prefix: string }) {
  const queryClient = useQueryClient()
  const [notice, setNotice] = useState<string | null>(payload.message || null)
  const queryKey = ["repositories", String(payload.repository.id), "documents"] as const
  const destroy = useMutation({
    mutationFn: (document: RepositoryDocument) => deleteRepositoryDocument(document.id),
    onSuccess: (updated) => {
      queryClient.setQueryData(queryKey, updated)
      setNotice(updated.message || "Document removed.")
    }
  })

  return (
    <>
      <header>
        <h1 className="font-mono text-2xl font-semibold text-gray-900">
          <Link className="hover:underline" to={`${prefix}${payload.repository.repository_path}`}>{payload.repository.slug}</Link>
        </h1>
        <p className="mt-1 text-sm text-gray-600">Supporting documents available to agent runs for this repository.</p>
      </header>

      <RepositoryTabs active="documents" prefix={prefix} repositoryId={payload.repository.id} />

      <NoticeToast message={notice} onDismiss={() => setNotice(null)} />
      {destroy.isError ? <PanelMessage tone="error">{errorMessage(destroy.error, "Unable to delete document.")}</PanelMessage> : null}

      <section className="rounded border border-gray-200 bg-white">
        <div className="border-b border-gray-200 px-4 py-3">
          <h2 className="text-sm font-semibold text-gray-900">Documentation</h2>
        </div>

        {payload.documents.length === 0 ? (
          <div className="m-4 rounded border border-dashed border-gray-300 px-4 py-8 text-center text-sm text-gray-600">
            No supporting documents yet. Upload a file or link a Google Doc to give the agent extra context.
          </div>
        ) : (
          <ul className="divide-y divide-gray-100 px-4">
            {payload.documents.map((document) => (
              <li className="py-3" key={document.id}>
                <div className="flex items-start gap-3">
                  <DocumentBadge document={document} />
                  <DocumentSummary document={document} />
                  <button
                    className="shrink-0 rounded bg-gray-100 px-2 py-1 text-xs font-medium text-gray-700 hover:bg-gray-200 disabled:text-gray-300"
                    disabled={destroy.isPending}
                    onClick={() => {
                      if (window.confirm("Delete this document?")) destroy.mutate(document)
                    }}
                    type="button"
                  >
                    Delete
                  </button>
                </div>
              </li>
            ))}
          </ul>
        )}
      </section>

      <DocumentForms acceptedTypes={payload.accepted_file_content_types} onNotice={setNotice} payload={payload} />
    </>
  )
}

function DocumentForms({
  payload,
  acceptedTypes,
  onNotice
}: {
  payload: RepositoryDocumentsPayload
  acceptedTypes: string[]
  onNotice: (message: string | null) => void
}) {
  const queryClient = useQueryClient()
  const queryKey = ["repositories", String(payload.repository.id), "documents"] as const
  const [fileTitle, setFileTitle] = useState("")
  const [file, setFile] = useState<File | null>(null)
  const [docTitle, setDocTitle] = useState("")
  const [googleDocUrl, setGoogleDocUrl] = useState("")
  const save = useMutation({
    mutationFn: (input: RepositoryDocumentInput) => createRepositoryDocument(payload.repository.id, input),
    onSuccess: (updated) => {
      queryClient.setQueryData(queryKey, updated)
      setFileTitle("")
      setFile(null)
      setDocTitle("")
      setGoogleDocUrl("")
      onNotice(updated.message || "Document added.")
    }
  })

  function submitFile(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    onNotice(null)
    save.mutate({ kind: "file", title: fileTitle, google_docs_url: "", file })
  }

  function submitGoogleDoc(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    onNotice(null)
    save.mutate({ kind: "google_doc", title: docTitle, google_docs_url: googleDocUrl, file: null })
  }

  return (
    <section className="grid gap-4 md:grid-cols-2">
      {save.isError ? <div className="md:col-span-2"><PanelMessage tone="error">{errorMessage(save.error, "Unable to add document.")}</PanelMessage></div> : null}

      <form className="space-y-3 rounded border border-gray-200 bg-white p-4" onSubmit={submitFile}>
        <h2 className="text-sm font-semibold text-gray-900">Upload a file</h2>
        <Field label="File title">
          <input className={inputClass()} onChange={(event) => setFileTitle(event.target.value)} placeholder="Optional; defaults to filename" type="text" value={fileTitle} />
        </Field>
        <Field label="File">
          <input accept={acceptedTypes.join(",")} className="block w-full text-sm text-gray-700" onChange={(event) => setFile(event.currentTarget.files?.[0] || null)} required type="file" />
        </Field>
        <button className={primaryButton()} disabled={save.isPending} type="submit">{save.isPending ? "Uploading..." : "Upload"}</button>
      </form>

      <form className="space-y-3 rounded border border-gray-200 bg-white p-4" onSubmit={submitGoogleDoc}>
        <h2 className="text-sm font-semibold text-gray-900">Link a Google Doc</h2>
        <Field label="URL">
          <input className={inputClass()} onChange={(event) => setGoogleDocUrl(event.target.value)} placeholder="https://docs.google.com/document/..." required type="url" value={googleDocUrl} />
        </Field>
        <Field label="Document title">
          <input className={inputClass()} onChange={(event) => setDocTitle(event.target.value)} placeholder="Optional" type="text" value={docTitle} />
        </Field>
        <button className={primaryButton()} disabled={save.isPending} type="submit">{save.isPending ? "Adding..." : "Add Google Doc"}</button>
      </form>
    </section>
  )
}

function DocumentBadge({ document }: { document: RepositoryDocument }) {
  let label = "DOC"
  if (document.kind === "google_doc") label = "G"
  if (document.content_type?.startsWith("image/")) label = "IMG"
  if (document.content_type === "application/pdf") label = "PDF"

  return (
    <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded border border-gray-200 bg-gray-50 text-xs font-semibold text-gray-600">
      {label}
    </div>
  )
}

function DocumentSummary({ document }: { document: RepositoryDocument }) {
  return (
    <div className="min-w-0 flex-1">
      <div className="break-words text-sm font-medium text-gray-900">{document.title}</div>
      <div className="mt-1 break-all text-xs text-gray-500">
        {document.kind === "google_doc" && document.google_doc_url ? (
          <a className="text-blue-600 underline hover:no-underline" href={document.google_doc_url} rel="noopener" target="_blank">{document.google_doc_url}</a>
        ) : (
          <span>{document.filename || "No file attached"}{document.byte_size ? ` · ${formatBytes(document.byte_size)}` : ""}</span>
        )}
      </div>
      <div className="mt-1 text-xs text-gray-500">{document.uploaded_by || "Unknown"} · {new Date(document.created_at).toLocaleString()}</div>
    </div>
  )
}

function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <label className="block text-sm font-medium text-gray-700">
      {label}
      <div className="mt-1">{children}</div>
    </label>
  )
}

function RepositoryDocumentsError({ error }: { error: Error }) {
  return <PanelMessage tone="error">{errorMessage(error, "Unable to load repository documents.")}</PanelMessage>
}

function PanelMessage({ children, tone = "muted" }: { children: ReactNode; tone?: "muted" | "error" | "success" }) {
  const colors = {
    error: "border-red-200 bg-red-50 text-red-700",
    success: "border-green-200 bg-green-50 text-green-700",
    muted: "border-gray-200 bg-white text-gray-600"
  }
  return <div className={`rounded border p-4 text-sm ${colors[tone]}`}>{children}</div>
}

function inputClass() {
  return "block w-full rounded border border-gray-300 px-3 py-2 text-sm shadow-sm focus:outline-blue-600"
}

function primaryButton() {
  return "rounded bg-blue-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-blue-500 disabled:cursor-not-allowed disabled:bg-blue-300"
}

function routePrefix(pathname: string) {
  return pathname.startsWith("/app-shell") ? "/app-shell" : ""
}

function formatBytes(value: number) {
  if (value < 1024) return `${value} B`
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KB`
  return `${(value / (1024 * 1024)).toFixed(1)} MB`
}

function errorMessage(error: Error, fallback: string) {
  return error instanceof ApiError ? error.message : fallback
}
