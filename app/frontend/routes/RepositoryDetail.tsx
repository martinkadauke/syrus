import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"
import type { FormEvent, ReactNode } from "react"
import { useState } from "react"
import { useLocation, useNavigate, useParams } from "react-router-dom"
import { ApiError } from "../api/client"
import {
  archiveRepositoryFromPath,
  bulkRepositoryIssues,
  closeRepositoryIssue,
  commentRepositoryIssue,
  createRepositoryNote,
  deleteRepositoryNote,
  delegateRepositoryIssue,
  fetchRepositoryDetail,
  fetchRepositoryIssues,
  pollRepositoryDetail,
  retryFailedRepositoryJobs,
  type RepositoryDetailJob,
  type RepositoryDetailPayload,
  type RepositoryIssue,
  type RepositoryIssuesPayload
} from "../api/repositories"

type IssueCommand =
  | { kind: "close"; issueNumber: number }
  | { kind: "delegate"; issueNumber: number }
  | { kind: "bulk"; bulkAction: "close" | "delegate"; issueNumbers: number[] }
  | { kind: "comment"; issueNumber: number; commentBody: string }

export function RepositoryDetailRoute() {
  const params = useParams()
  const location = useLocation()
  const id = params.id || ""
  const query = new URLSearchParams(location.search)
  const tab = query.get("tab") === "github_issues" ? "github_issues" : "overview"
  const state = query.get("state") === "closed" ? "closed" : "open"
  const search = pageSearch(location.search)
  const detailQueryKey = repositoryDetailQueryKey(id, search)
  const detail = useQuery({
    queryKey: detailQueryKey,
    queryFn: () => fetchRepositoryDetail(id, search),
    enabled: id.length > 0 && tab === "overview"
  })
  const issues = useQuery({
    queryKey: ["repositories", id, "issues", state],
    queryFn: () => fetchRepositoryIssues(id, state),
    enabled: id.length > 0 && tab === "github_issues"
  })

  return (
    <main aria-label="Repository" className="mx-auto max-w-7xl space-y-6 p-6">
      {tab === "overview" ? (
        <>
          {detail.isPending ? <PanelMessage>Loading repository...</PanelMessage> : null}
          {detail.isError ? <PanelMessage tone="error">{errorMessage(detail.error, "Unable to load repository.")}</PanelMessage> : null}
          {detail.isSuccess ? <RepositoryDetail payload={detail.data} queryKey={detailQueryKey} /> : null}
        </>
      ) : (
        <>
          {issues.isPending ? <PanelMessage>Loading GitHub issues...</PanelMessage> : null}
          {issues.isError ? <PanelMessage tone="error">{errorMessage(issues.error, "Unable to load GitHub issues.")}</PanelMessage> : null}
          {issues.isSuccess ? <RepositoryIssues payload={issues.data} /> : null}
        </>
      )}
    </main>
  )
}

type RepositoryDetailQueryKey = readonly ["repositories", string, "detail", string]

function repositoryDetailQueryKey(id: string | number, search: string): RepositoryDetailQueryKey {
  return ["repositories", String(id), "detail", search] as const
}

function appendSearch(path: string, search: string) {
  return search ? `${path}${search}` : path
}

function RepositoryDetail({ payload, queryKey }: { payload: RepositoryDetailPayload; queryKey: RepositoryDetailQueryKey }) {
  const [notice, setNotice] = useState<string | null>(payload.message || null)

  return (
    <>
      <header>
        <h1 className="break-words font-mono text-3xl font-semibold text-gray-900">
          <a className="hover:underline" href={payload.repository.github_url} rel="noopener" target="_blank">{payload.repository.slug}</a>
        </h1>
      </header>

      <Tabs active="overview" tabs={payload.tabs} />
      {notice ? <PanelMessage>{notice}</PanelMessage> : null}
      <Metadata payload={payload} />
      <Actions payload={payload} queryKey={queryKey} onNotice={setNotice} />
      <CredentialNotice payload={payload} />
      <Counts payload={payload} />
      <Notes payload={payload} queryKey={queryKey} onNotice={setNotice} />
      <RecentJobs payload={payload} />
    </>
  )
}

function RepositoryIssues({ payload }: { payload: RepositoryIssuesPayload }) {
  const queryClient = useQueryClient()
  const queryKey = ["repositories", String(payload.repository.id), "issues", payload.state] as const
  const [notice, setNotice] = useState<string | null>(payload.message || null)
  const [selected, setSelected] = useState<number[]>([])
  const [commentingOn, setCommentingOn] = useState<RepositoryIssue | null>(null)
  const [commentBody, setCommentBody] = useState("")
  const command = useMutation({
    mutationFn: (action: IssueCommand) => {
      switch (action.kind) {
        case "close":
          return closeRepositoryIssue(payload.paths.app_close_issue_path, { issueNumber: action.issueNumber, state: payload.state })
        case "delegate":
          return delegateRepositoryIssue(payload.paths.app_delegate_issue_path, { issueNumber: action.issueNumber, state: payload.state })
        case "comment":
          return commentRepositoryIssue(payload.paths.app_comment_issue_path, { issueNumber: action.issueNumber, commentBody: action.commentBody, state: payload.state })
        case "bulk":
          return bulkRepositoryIssues(payload.paths.app_bulk_issues_path, { issueNumbers: action.issueNumbers, bulkAction: action.bulkAction, state: payload.state })
      }
    },
    onSuccess: (updated) => {
      queryClient.setQueryData(queryKey, updated)
      setNotice(updated.message || null)
      setSelected([])
      setCommentingOn(null)
      setCommentBody("")
    }
  })

  function toggleIssue(number: number) {
    setSelected((current) => current.includes(number) ? current.filter((value) => value !== number) : [...current, number])
  }

  function submitComment(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!commentingOn) return
    command.mutate({ kind: "comment", issueNumber: commentingOn.number, commentBody })
  }

  return (
    <>
      <header>
        <h1 className="break-words font-mono text-3xl font-semibold text-gray-900">
          <a className="hover:underline" href={payload.repository.github_url} rel="noopener" target="_blank">{payload.repository.slug}</a>
        </h1>
      </header>

      <Tabs active="github_issues" tabs={payload.tabs} />

      <div className="flex flex-wrap gap-x-5 gap-y-1 text-sm text-gray-600">
        <span>Trigger label: <code className="rounded bg-gray-100 px-1">{payload.repository.trigger_label}</code></span>
        <span>Showing: <StatusPill tone={payload.state === "open" ? "green" : "gray"}>{payload.state}</StatusPill></span>
        <span><strong>{payload.issue_count}</strong> {payload.issue_count === 1 ? "issue" : "issues"}</span>
        {payload.repository.github_rate_limit ? (
          <span>
            GitHub quota: <strong>{payload.repository.github_rate_limit.remaining.toLocaleString()}</strong> / {payload.repository.github_rate_limit.limit.toLocaleString()} ({payload.repository.github_rate_limit.resource})
          </span>
        ) : null}
        <a className="text-blue-600 hover:underline" href={payload.paths.github_issues_path} rel="noopener" target="_blank">View on GitHub</a>
      </div>

      {notice ? <PanelMessage>{notice}</PanelMessage> : null}
      {payload.error_message ? <PanelMessage tone="error">{payload.error_message}</PanelMessage> : null}
      {command.isError ? <PanelMessage tone="error">{errorMessage(command.error, "GitHub issue command failed.")}</PanelMessage> : null}

      <div className="flex items-center justify-between gap-3">
        <div className="flex gap-1">
          <a className={stateFilterClass(payload.state === "open")} href={payload.state_paths.open}>Open</a>
          <a className={stateFilterClass(payload.state === "closed")} href={payload.state_paths.closed}>Closed</a>
        </div>
        {payload.issues.length > 0 ? (
          <div className="flex flex-wrap justify-end gap-2">
            {payload.state === "open" ? (
              <button
                className="rounded border border-amber-200 bg-amber-50 px-3 py-1.5 text-sm font-medium text-amber-700 hover:bg-amber-100 disabled:opacity-50"
                disabled={selected.length === 0 || command.isPending}
                onClick={() => command.mutate({ kind: "bulk", bulkAction: "close", issueNumbers: selected })}
                type="button"
              >
                Close selected
              </button>
            ) : null}
            <button
              className="rounded border border-blue-200 bg-blue-50 px-3 py-1.5 text-sm font-medium text-blue-700 hover:bg-blue-100 disabled:opacity-50"
              disabled={selected.length === 0 || command.isPending}
              onClick={() => command.mutate({ kind: "bulk", bulkAction: "delegate", issueNumbers: selected })}
              type="button"
            >
              Delegate selected
            </button>
          </div>
        ) : null}
      </div>

      {payload.issues.length > 0 ? (
        <div className="overflow-hidden rounded border border-gray-200 bg-white">
          <table className="min-w-full divide-y divide-gray-200">
            <thead className="bg-gray-50 text-left text-xs uppercase text-gray-500">
              <tr>
                <th className="w-10 px-4 py-2"><span className="sr-only">Select</span></th>
                <th className="px-4 py-2">Issue</th>
                <th className="w-36 px-4 py-2 text-right">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100 text-sm">
              {payload.issues.map((issue) => (
                <RepositoryIssueRow
                  commandPending={command.isPending}
                  issue={issue}
                  key={issue.number}
                  onClose={() => command.mutate({ kind: "close", issueNumber: issue.number })}
                  onComment={() => {
                    setCommentingOn(issue)
                    setCommentBody("")
                  }}
                  onDelegate={() => command.mutate({ kind: "delegate", issueNumber: issue.number })}
                  onToggle={() => toggleIssue(issue.number)}
                  selected={selected.includes(issue.number)}
                  state={payload.state}
                />
              ))}
            </tbody>
          </table>
        </div>
      ) : (
        <div className="rounded border border-gray-200 bg-white p-6 text-sm text-gray-600">No {payload.state} issues found.</div>
      )}

      {commentingOn ? (
        <section className="rounded border border-gray-200 bg-white p-4">
          <h2 className="text-base font-semibold text-gray-900">Comment on <span className="font-mono text-sm font-normal text-gray-600">#{commentingOn.number}</span></h2>
          <form className="mt-3 space-y-3" onSubmit={submitComment}>
            <textarea
              className="w-full rounded border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              onChange={(event) => setCommentBody(event.target.value)}
              rows={5}
              value={commentBody}
            />
            <div className="flex justify-end gap-2">
              <button className="rounded border border-gray-300 px-3 py-1.5 text-sm text-gray-700 hover:bg-gray-50" onClick={() => setCommentingOn(null)} type="button">Cancel</button>
              <button className={buttonClass("blue")} disabled={command.isPending} type="submit">Post comment</button>
            </div>
          </form>
        </section>
      ) : null}
    </>
  )
}

function RepositoryIssueRow({
  commandPending,
  issue,
  onClose,
  onComment,
  onDelegate,
  onToggle,
  selected,
  state
}: {
  commandPending: boolean
  issue: RepositoryIssue
  onClose: () => void
  onComment: () => void
  onDelegate: () => void
  onToggle: () => void
  selected: boolean
  state: "open" | "closed"
}) {
  return (
    <tr>
      <td className="px-4 py-3 align-top">
        <input aria-label={`Select issue #${issue.number}`} checked={selected} className="rounded border-gray-300 text-blue-600 focus:ring-blue-500" onChange={onToggle} type="checkbox" />
      </td>
      <td className="px-4 py-3 align-top">
        <div className="flex flex-wrap items-baseline gap-2">
          <a className="font-mono text-gray-500 hover:underline" href={issue.html_url} rel="noopener" target="_blank">#{issue.number}</a>
          {issue.labels.map((label) => <IssueLabel color={label.color} key={label.name} name={label.name} />)}
          <a className="font-medium text-gray-900 hover:underline" href={issue.html_url} rel="noopener" target="_blank">{issue.title}</a>
        </div>
        <div className="mt-1 text-xs text-gray-500">{issue.user_login ? `${issue.user_login} · ` : ""}{issue.created_at ? formatRelative(issue.created_at) : ""}</div>
        {issue.body_excerpt ? <p className="mt-1 line-clamp-2 text-xs text-gray-400">{issue.body_excerpt}</p> : null}
      </td>
      <td className="px-4 py-3 align-top">
        <div className="flex flex-col items-stretch gap-1.5">
          <button className="rounded bg-gray-100 px-2 py-1 text-xs font-medium text-gray-700 hover:bg-gray-200" disabled={commandPending} onClick={onComment} type="button">Comment</button>
          {state === "open" ? <button className="rounded bg-amber-50 px-2 py-1 text-xs font-medium text-amber-700 hover:bg-amber-100" disabled={commandPending} onClick={onClose} type="button">Close</button> : null}
          {issue.delegated ? (
            <span className="rounded border border-green-200 bg-green-50 px-2 py-1 text-center text-xs font-medium text-green-700">Delegated</span>
          ) : (
            <button className="rounded bg-blue-50 px-2 py-1 text-xs font-medium text-blue-700 hover:bg-blue-100" disabled={commandPending} onClick={onDelegate} type="button">Delegate</button>
          )}
        </div>
      </td>
    </tr>
  )
}

function IssueLabel({ color, name }: { color: string; name: string }) {
  const safeColor = color.match(/^[0-9a-fA-F]{6}$/) ? color : "6b7280"
  return (
    <span
      className="inline-flex items-center rounded px-1.5 py-0.5 text-xs font-medium"
      style={{
        backgroundColor: `#${safeColor}22`,
        border: `1px solid #${safeColor}44`,
        color: `#${safeColor}`
      }}
    >
      {name}
    </span>
  )
}

function Tabs({ active, tabs }: { active: string; tabs: Array<{ key: string; label: string; path: string }> }) {
  return (
    <nav className="flex flex-wrap border-b border-gray-200" aria-label="Repository tabs">
      {tabs.map((tab) => (
        <a
          className={`-mb-px border-b-2 px-4 py-2 text-sm font-medium ${tab.key === active ? "border-blue-600 text-blue-600" : "border-transparent text-gray-600 hover:border-gray-300 hover:text-gray-900"}`}
          href={tab.path}
          key={tab.key}
        >
          {tab.label}
        </a>
      ))}
    </nav>
  )
}

function Metadata({ payload }: { payload: RepositoryDetailPayload }) {
  const repository = payload.repository
  return (
    <div className="flex flex-wrap gap-x-5 gap-y-1 text-sm text-gray-600">
      <span>Branch: <span className="font-mono">{repository.default_branch}</span></span>
      <span>
        <StatusPill tone={repository.polling_enabled ? "green" : "gray"}>{repository.polling_enabled ? "polling enabled" : "polling paused"}</StatusPill>
        <span className="mx-1 text-gray-300">·</span>
        label <code className="rounded bg-gray-100 px-1">{repository.trigger_label}</code>
      </span>
      <span>
        Owner: {repository.owner_user.email_address}
        {repository.owner_user.admin ? <span className="ml-1 rounded bg-purple-100 px-1.5 py-0.5 text-xs text-purple-700">admin</span> : null}
      </span>
      <span>
        Agent: {repository.agent_provider_label || `user default (${repository.effective_agent_provider_label})`}
      </span>
      {repository.github_rate_limit ? (
        <span>
          GitHub quota: <strong>{repository.github_rate_limit.remaining.toLocaleString()}</strong> / {repository.github_rate_limit.limit.toLocaleString()} ({repository.github_rate_limit.resource})
        </span>
      ) : null}
      <span>Added: {formatDate(repository.created_at)}</span>
      <span>{payload.credential_status.mode === "app" ? `Syrus App installed (via ${payload.credential_status.installation_account})` : "PAT fallback"}</span>
    </div>
  )
}

function Actions({ payload, queryKey, onNotice }: { payload: RepositoryDetailPayload; queryKey: RepositoryDetailQueryKey; onNotice: (message: string | null) => void }) {
  const queryClient = useQueryClient()
  const navigate = useNavigate()
  const search = queryKey[3]
  const retry = payload.retry_failed_jobs
  const poll = useMutation({
    mutationFn: () => pollRepositoryDetail(appendSearch(payload.paths.app_poll_repository_path, search), payload.pagination.page),
    onSuccess: (updated) => {
      queryClient.setQueryData(queryKey, updated)
      onNotice(updated.message || null)
    }
  })
  const retryFailed = useMutation({
    mutationFn: () => retryFailedRepositoryJobs(appendSearch(payload.paths.app_retry_failed_jobs_repository_path, search), payload.pagination.page),
    onSuccess: (updated) => {
      queryClient.setQueryData(queryKey, updated)
      onNotice(updated.message || null)
    }
  })
  const archive = useMutation({
    mutationFn: () => archiveRepositoryFromPath(payload.paths.app_archive_repository_path),
    onSuccess: (updated) => {
      queryClient.setQueryData(["repositories"], updated)
      navigate(payload.paths.repositories_path)
    }
  })
  const disabled = poll.isPending || retryFailed.isPending || archive.isPending

  function archiveRepository() {
    onNotice(null)
    if (window.confirm(`Archive ${payload.repository.slug}? Polling stops; existing jobs are unaffected.`)) {
      archive.mutate()
    }
  }

  return (
    <>
      <div className="flex flex-wrap items-center gap-2">
        <a className={buttonClass("green")} href={payload.paths.new_job_path}>New job</a>
        <button className={buttonClass("blue")} disabled={disabled} onClick={() => { onNotice(null); poll.mutate() }} type="button">Poll now</button>
        {retry.count > 0 ? (
          <button className={buttonClass("amber")} disabled={disabled} onClick={() => { onNotice(null); retryFailed.mutate() }} type="button">Retry {retry.count} failed with {retry.agent_provider_label}</button>
        ) : null}
        <a className={buttonClass("gray")} href={payload.paths.edit_repository_path}>Edit</a>
        <button className="rounded bg-amber-50 px-3 py-1.5 text-sm font-medium text-amber-800 hover:bg-amber-100 disabled:text-gray-300" disabled={disabled} onClick={archiveRepository} type="button">Archive</button>
        <a className={buttonClass("gray")} href={payload.paths.repository_documents_path}>Documents</a>
        <a className={buttonClass("gray")} href={payload.paths.repository_scheduled_tasks_path}>Scheduled Tasks</a>
      </div>
      {poll.isError ? <PanelMessage tone="error">{errorMessage(poll.error, "Repository poll failed.")}</PanelMessage> : null}
      {retryFailed.isError ? <PanelMessage tone="error">{errorMessage(retryFailed.error, "Retry failed jobs command failed.")}</PanelMessage> : null}
      {archive.isError ? <PanelMessage tone="error">{errorMessage(archive.error, "Archive failed.")}</PanelMessage> : null}
    </>
  )
}

function CredentialNotice({ payload }: { payload: RepositoryDetailPayload }) {
  const status = payload.credential_status
  if (status.mode === "app") return null

  return (
    <section className="rounded border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
      <div className="font-semibold">{status.github_app_registered ? "This repository is using personal-token fallback." : "Syrus App is not registered."}</div>
      {status.previous_installation_removed ? <p className="mt-1">Its previous installation was removed.</p> : null}
      {status.install_url ? <a className={buttonClass("amber", "mt-3 inline-block")} href={status.install_url} rel="noopener" target="_blank">Install Syrus App on this repository</a> : null}
      {status.missing_github_ids ? <p className="mt-2 text-xs">GitHub numeric IDs are missing; edit this repository and select it from the GitHub-backed picker to generate a one-click install link.</p> : null}
      {status.register_path ? <a className={buttonClass("amber", "mt-3 inline-block")} href={status.register_path}>Register Syrus App</a> : null}
    </section>
  )
}

function Counts({ payload }: { payload: RepositoryDetailPayload }) {
  return (
    <section className="grid grid-cols-3 gap-4">
      <CountBox label="Running" tone="blue" value={payload.counts.running} />
      <CountBox label="Queued" tone="gray" value={payload.counts.queued} />
      <CountBox label="Failed (7d)" tone="red" value={payload.counts.failed_7d} />
    </section>
  )
}

function CountBox({ label, tone, value }: { label: string; tone: "blue" | "gray" | "red"; value: number }) {
  const colors = {
    blue: "text-blue-600",
    gray: "text-gray-600",
    red: "text-red-600"
  }
  return (
    <div className="rounded border border-gray-200 bg-white p-4 text-center">
      <div className={`text-2xl font-bold ${colors[tone]}`}>{value}</div>
      <div className="mt-1 text-xs uppercase text-gray-500">{label}</div>
    </div>
  )
}

function Notes({ payload, queryKey, onNotice }: { payload: RepositoryDetailPayload; queryKey: RepositoryDetailQueryKey; onNotice: (message: string | null) => void }) {
  const queryClient = useQueryClient()
  const search = queryKey[3]
  const [body, setBody] = useState("")
  const create = useMutation({
    mutationFn: () => createRepositoryNote(appendSearch(payload.paths.app_repository_notes_path, search), body),
    onSuccess: (updated) => {
      queryClient.setQueryData(queryKey, updated)
      setBody("")
      onNotice(updated.message || null)
    }
  })
  const remove = useMutation({
    mutationFn: (path: string) => deleteRepositoryNote(appendSearch(path, search)),
    onSuccess: (updated) => {
      queryClient.setQueryData(queryKey, updated)
      onNotice(updated.message || null)
    }
  })

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    create.mutate()
  }

  return (
    <section className="overflow-hidden rounded border border-gray-200 bg-white">
      <div className="border-b border-gray-200 px-4 py-3">
        <h2 className="text-lg font-semibold text-gray-900">Notes</h2>
      </div>
      <div className="space-y-4 p-4">
        {payload.notes.length > 0 ? (
          <ul className="divide-y divide-gray-100">
            {payload.notes.map((note) => (
              <li className="flex items-start justify-between gap-4 py-3 first:pt-0 last:pb-0" key={note.id}>
                <div className="min-w-0">
                  <p className="whitespace-pre-wrap break-words text-sm text-gray-800">{note.body}</p>
                  <p className="mt-1 text-xs text-gray-500">{note.author} · {formatRelative(note.created_at)}</p>
                </div>
                <button
                  className="rounded bg-gray-100 px-2 py-1 text-xs font-medium text-gray-700 hover:bg-gray-200 disabled:text-gray-300"
                  disabled={remove.isPending}
                  onClick={() => remove.mutate(note.app_delete_path)}
                  type="button"
                >
                  Delete
                </button>
              </li>
            ))}
          </ul>
        ) : <p className="text-sm text-gray-600">No notes pinned yet.</p>}

        <form className="flex flex-col gap-2 sm:flex-row" onSubmit={submit}>
          <textarea className="min-h-20 flex-1 rounded border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" name="repository_note[body]" onChange={(event) => setBody(event.target.value)} placeholder="Pin repository context..." required rows={2} value={body} />
          <div className="sm:self-end">
            <button className={buttonClass("blue", "w-full sm:w-auto")} disabled={create.isPending} type="submit">Add note</button>
          </div>
        </form>
        {create.isError ? <div className="text-sm text-red-700">{errorMessage(create.error, "Repository note could not be added.")}</div> : null}
        {remove.isError ? <div className="text-sm text-red-700">{errorMessage(remove.error, "Repository note could not be removed.")}</div> : null}
      </div>
    </section>
  )
}

function RecentJobs({ payload }: { payload: RepositoryDetailPayload }) {
  if (payload.jobs.length === 0) {
    return (
      <section>
        <h2 className="mb-3 text-lg font-semibold text-gray-900">Recent jobs</h2>
        <div className="rounded border border-gray-200 bg-white p-6 text-sm text-gray-600">
          No jobs yet. Enable polling or label an issue <code className="rounded bg-gray-100 px-1">{payload.repository.trigger_label}</code> in this repo.
        </div>
      </section>
    )
  }

  return (
    <section>
      <h2 className="mb-3 text-lg font-semibold text-gray-900">Recent jobs</h2>
      <div className="overflow-hidden rounded border border-gray-200 bg-white">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="bg-gray-50 text-left text-xs uppercase text-gray-500">
            <tr>
              <th className="px-4 py-2">State</th>
              <th className="px-4 py-2">Issue</th>
              <th className="hidden px-4 py-2 sm:table-cell">Runs</th>
              <th className="hidden px-4 py-2 sm:table-cell">Last</th>
              <th className="hidden px-4 py-2 sm:table-cell"><span className="sr-only">Actions</span></th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100 text-sm">
            {payload.jobs.map((job) => <JobRow job={job} key={job.id} />)}
          </tbody>
        </table>
      </div>
      <Pagination payload={payload} />
    </section>
  )
}

function JobRow({ job }: { job: RepositoryDetailJob }) {
  return (
    <tr>
      <td className="px-4 py-3 align-top">
        <StatusPill tone={stateTone(job.state)}>{job.state}</StatusPill>
        {job.priority !== "medium" ? <span className="ml-1"><StatusPill tone="gray">{job.priority}</StatusPill></span> : null}
      </td>
      <td className="px-4 py-3">
        <SourceLink job={job} />
        {job.issue_title ? <a className="ml-1 text-gray-700 hover:underline" href={job.job_path}>{job.issue_title}</a> : null}
        {job.pr_number && job.pr_url ? <a className="ml-1 text-xs text-indigo-700 underline hover:no-underline" href={job.pr_url} rel="noopener" target="_blank">PR #{job.pr_number}</a> : null}
        {job.external_pr_number && job.external_pr_url ? <a className="ml-1 text-xs text-violet-700 underline hover:no-underline" href={job.external_pr_url} rel="noopener" target="_blank">PR #{job.external_pr_number}</a> : null}
        {job.current_step_caption ? <div className="mt-0.5 text-xs italic text-gray-500">{job.current_step_caption}</div> : null}
        <div className="mt-1 flex items-center gap-1.5 text-xs text-gray-400 sm:hidden">
          <span>{job.runs_count} {job.runs_count === 1 ? "run" : "runs"}</span>
          <span>·</span>
          <span>{formatRelative(job.updated_at)}</span>
        </div>
      </td>
      <td className="hidden px-4 py-3 text-gray-600 sm:table-cell">{job.runs_count}</td>
      <td className="hidden px-4 py-3 text-gray-500 sm:table-cell">{formatRelative(job.updated_at)}</td>
      <td className="hidden px-4 py-3 text-right sm:table-cell"><a className="text-blue-600 underline hover:no-underline" href={job.job_path}>View</a></td>
    </tr>
  )
}

function SourceLink({ job }: { job: RepositoryDetailJob }) {
  if (!job.source.path) return <span className="text-gray-600">{job.source.label}</span>
  return (
    <a className="text-blue-600 underline hover:no-underline" href={job.source.path} rel={job.source.external ? "noopener" : undefined} target={job.source.external ? "_blank" : undefined}>
      {job.source.label}
    </a>
  )
}

function Pagination({ payload }: { payload: RepositoryDetailPayload }) {
  const pagination = payload.pagination
  if (pagination.total_pages <= 1) return null

  return (
    <div className="mt-4 flex items-center justify-between text-sm text-gray-600">
      <span>Showing {pagination.first_item}-{pagination.last_item} of {pagination.total_jobs}</span>
      <div className="flex gap-2">
        {pagination.previous_path ? <a className={paginationLinkClass()} href={pagination.previous_path}>Previous</a> : <span className={disabledPaginationClass()}>Previous</span>}
        {pagination.next_path ? <a className={paginationLinkClass()} href={pagination.next_path}>Next</a> : <span className={disabledPaginationClass()}>Next</span>}
      </div>
    </div>
  )
}

function StatusPill({ children, tone }: { children: ReactNode; tone: "green" | "gray" | "blue" | "red" | "amber" }) {
  const colors = {
    amber: "bg-amber-100 text-amber-700",
    blue: "bg-blue-100 text-blue-700",
    gray: "bg-gray-100 text-gray-600",
    green: "bg-green-100 text-green-700",
    red: "bg-red-100 text-red-700"
  }
  return <span className={`inline-block rounded px-2 py-0.5 text-xs font-medium ${colors[tone]}`}>{children}</span>
}

function PanelMessage({ children, tone = "muted" }: { children: ReactNode; tone?: "muted" | "error" }) {
  const colors = {
    error: "border-red-200 bg-red-50 text-red-700",
    muted: "border-gray-200 bg-white text-gray-600"
  }
  return <div className={`rounded border p-4 text-sm ${colors[tone]}`}>{children}</div>
}

function buttonClass(tone: "green" | "blue" | "amber" | "gray", extra = "") {
  const colors = {
    amber: "bg-amber-600 text-white hover:bg-amber-500",
    blue: "bg-blue-600 text-white hover:bg-blue-500",
    gray: "bg-gray-100 text-gray-700 hover:bg-gray-200",
    green: "bg-emerald-600 text-white hover:bg-emerald-500"
  }
  return `rounded px-3 py-1.5 text-sm font-medium ${colors[tone]} ${extra}`.trim()
}

function stateTone(state: string) {
  if (state === "running") return "blue"
  if (state === "failed" || state === "landing_failed") return "red"
  if (state === "closed" || state === "preempted") return "gray"
  if (state === "queued") return "gray"
  if (state === "approved" || state === "landing" || state === "merged") return "green"
  return "amber"
}

function paginationLinkClass() {
  return "rounded border border-gray-300 px-3 py-1 hover:bg-gray-50"
}

function disabledPaginationClass() {
  return "rounded border border-gray-200 px-3 py-1 text-gray-300"
}

function stateFilterClass(active: boolean) {
  return `rounded border px-3 py-1.5 text-sm font-medium ${active ? "border-blue-600 bg-blue-600 text-white" : "border-gray-300 bg-white text-gray-700 hover:bg-gray-50"}`
}

function pageSearch(search: string) {
  const params = new URLSearchParams(search)
  const page = params.get("page")
  return page ? `?${new URLSearchParams({ page }).toString()}` : ""
}

function formatDate(value: string) {
  return new Intl.DateTimeFormat("en-US", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value))
}

function formatRelative(value: string) {
  const seconds = Math.max(0, Math.floor((Date.now() - new Date(value).getTime()) / 1000))
  if (seconds < 60) return "just now"
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return `${minutes}m ago`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}h ago`
  const days = Math.floor(hours / 24)
  return `${days}d ago`
}

function errorMessage(error: Error, fallback: string) {
  return error instanceof ApiError ? error.message : fallback
}
