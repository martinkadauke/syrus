import { useQuery } from "@tanstack/react-query"
import type { ReactNode } from "react"
import { useLocation, useParams } from "react-router-dom"
import { ApiError } from "../api/client"
import { fetchRepositoryDetail, type RepositoryDetailJob, type RepositoryDetailPayload } from "../api/repositories"

export function RepositoryDetailRoute() {
  const params = useParams()
  const location = useLocation()
  const id = params.id || ""
  const search = pageSearch(location.search)
  const repository = useQuery({
    queryKey: ["repositories", id, "detail", search],
    queryFn: () => fetchRepositoryDetail(id, search),
    enabled: id.length > 0
  })

  return (
    <main aria-label="Repository" className="mx-auto max-w-7xl space-y-6 p-6">
      {repository.isPending ? <PanelMessage>Loading repository...</PanelMessage> : null}
      {repository.isError ? <PanelMessage tone="error">{errorMessage(repository.error, "Unable to load repository.")}</PanelMessage> : null}
      {repository.isSuccess ? <RepositoryDetail payload={repository.data} /> : null}
    </main>
  )
}

function RepositoryDetail({ payload }: { payload: RepositoryDetailPayload }) {
  return (
    <>
      <header>
        <h1 className="break-words font-mono text-3xl font-semibold text-gray-900">
          <a className="hover:underline" href={payload.repository.github_url} rel="noopener" target="_blank">{payload.repository.slug}</a>
        </h1>
      </header>

      <Tabs payload={payload} />
      <Metadata payload={payload} />
      <Actions payload={payload} />
      <CredentialNotice payload={payload} />
      <Counts payload={payload} />
      <Notes payload={payload} />
      <RecentJobs payload={payload} />
    </>
  )
}

function Tabs({ payload }: { payload: RepositoryDetailPayload }) {
  return (
    <nav className="flex flex-wrap border-b border-gray-200" aria-label="Repository tabs">
      {payload.tabs.map((tab) => (
        <a
          className={`-mb-px border-b-2 px-4 py-2 text-sm font-medium ${tab.key === "overview" ? "border-blue-600 text-blue-600" : "border-transparent text-gray-600 hover:border-gray-300 hover:text-gray-900"}`}
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

function Actions({ payload }: { payload: RepositoryDetailPayload }) {
  const retry = payload.retry_failed_jobs
  return (
    <div className="flex flex-wrap items-center gap-2">
      <a className={buttonClass("green")} href={payload.paths.new_job_path}>New job</a>
      <PostForm action={payload.paths.poll_repository_path}><button className={buttonClass("blue")} type="submit">Poll now</button></PostForm>
      {retry.count > 0 ? (
        <PostForm action={payload.paths.retry_failed_jobs_repository_path}>
          <button className={buttonClass("amber")} type="submit">Retry {retry.count} failed with {retry.agent_provider_label}</button>
        </PostForm>
      ) : null}
      <a className={buttonClass("gray")} href={payload.paths.edit_repository_path}>Edit</a>
      <PostForm action={payload.paths.archive_repository_path}>
        <button className="rounded bg-amber-50 px-3 py-1.5 text-sm font-medium text-amber-800 hover:bg-amber-100" type="submit">Archive</button>
      </PostForm>
      <a className={buttonClass("gray")} href={payload.paths.repository_documents_path}>Documents</a>
      <a className={buttonClass("gray")} href={payload.paths.repository_scheduled_tasks_path}>Scheduled Tasks</a>
    </div>
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

function Notes({ payload }: { payload: RepositoryDetailPayload }) {
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
                <PostForm action={note.delete_path} method="delete">
                  <button className="rounded bg-gray-100 px-2 py-1 text-xs font-medium text-gray-700 hover:bg-gray-200" type="submit">Delete</button>
                </PostForm>
              </li>
            ))}
          </ul>
        ) : <p className="text-sm text-gray-600">No notes pinned yet.</p>}

        <form action={payload.paths.repository_notes_path} className="flex flex-col gap-2 sm:flex-row" method="post">
          <CsrfInput />
          <textarea className="min-h-20 flex-1 rounded border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" name="repository_note[body]" placeholder="Pin repository context..." required rows={2} />
          <div className="sm:self-end">
            <button className={buttonClass("blue", "w-full sm:w-auto")} type="submit">Add note</button>
          </div>
        </form>
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

function PostForm({ action, children, method = "post" }: { action: string; children: ReactNode; method?: "post" | "delete" }) {
  return (
    <form action={action} className="inline" method="post">
      <CsrfInput />
      {method !== "post" ? <input name="_method" type="hidden" value={method} /> : null}
      {children}
    </form>
  )
}

function CsrfInput() {
  const token = document.querySelector<HTMLMetaElement>("meta[name='csrf-token']")?.content || ""
  return <input name="authenticity_token" type="hidden" value={token} />
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
