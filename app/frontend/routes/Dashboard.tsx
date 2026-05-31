import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"
import { Link, useLocation } from "react-router-dom"
import { ApiError } from "../api/client"
import { fetchDashboard, updateDashboardPreferences, type DashboardEpicItem, type DashboardJobItem, type DashboardPayload, type DashboardSubject, type DashboardWorkflowItem } from "../api/dashboard"

export function DashboardRoute() {
  const location = useLocation()
  const search = dashboardApiSearch(location.pathname, location.search)
  const dashboard = useQuery({
    queryKey: ["dashboard", search],
    queryFn: () => fetchDashboard(search)
  })

  if (dashboard.isPending) return <main aria-label="Dashboard" className="p-6 text-sm text-gray-600">Loading...</main>
  if (dashboard.isError) return <DashboardError error={dashboard.error} />

  return <DashboardView pathname={location.pathname} search={location.search} payload={dashboard.data} />
}

function DashboardView({ payload, pathname, search }: { payload: DashboardPayload; pathname: string; search: string }) {
  const prefix = pathname.startsWith("/app-shell") ? "/app-shell" : ""

  return (
    <main aria-label="Dashboard" className="mx-auto max-w-7xl space-y-5 p-6">
      <header className="flex flex-wrap items-end justify-between gap-3 border-b border-gray-200 pb-4">
        <div>
          <h1 className="text-3xl font-semibold text-gray-900">Dashboard</h1>
          <p className="mt-1 text-sm text-gray-500">{payload.total} {subjectLabel(payload.subject, payload.total)} in this view</p>
        </div>
        <SubjectTabs payload={payload} prefix={prefix} />
      </header>

      <div className="grid gap-5 lg:grid-cols-[16rem_minmax(0,1fr)]">
        <SmartFolderNav payload={payload} prefix={prefix} />
        <section className="min-w-0 space-y-4">
          <DashboardToolbar pathname={pathname} search={search} payload={payload} />
          <DashboardTable payload={payload} />
          <Pagination pathname={pathname} search={search} payload={payload} />
        </section>
      </div>
    </main>
  )
}

function SubjectTabs({ payload, prefix }: { payload: DashboardPayload; prefix: string }) {
  const subjects: Array<{ key: DashboardSubject; label: string; count: number; path: string }> = [
    { key: "epic", label: "Epics", count: payload.counts.epics, path: "/dashboard/epics" },
    { key: "job", label: "Jobs", count: payload.counts.jobs, path: "/dashboard/jobs" },
    { key: "workflow", label: "Workflows", count: payload.counts.workflows, path: "/dashboard/workflows" }
  ]

  return (
    <nav aria-label="Dashboard subjects" className="flex flex-wrap gap-2">
      {subjects.map((subject) => (
        <Link
          className={`rounded border px-3 py-1.5 text-sm font-medium ${payload.subject === subject.key ? "border-blue-600 bg-blue-50 text-blue-700" : "border-gray-300 bg-white text-gray-700 hover:bg-gray-50"}`}
          key={subject.key}
          to={dashboardLink(`${prefix}${subject.path}`, { view: payload.view })}
        >
          {subject.label} <span className="text-gray-400">{subject.count}</span>
        </Link>
      ))}
    </nav>
  )
}

function SmartFolderNav({ payload, prefix }: { payload: DashboardPayload; prefix: string }) {
  return (
    <aside className="space-y-2">
      <h2 className="text-xs font-semibold uppercase text-gray-500">Smart folders</h2>
      <nav aria-label="Dashboard smart folders" className="space-y-1">
        <Link className={folderClass(payload.active_smart_folder_id == null)} to={dashboardLink(`${prefix}${subjectPath(payload.subject)}`, { view: payload.view })}>
          All {subjectLabel(payload.subject, 2)}
        </Link>
        {payload.smart_folders.map((folder) => (
          <Link className={folderClass(folder.active)} key={folder.id} to={withRoutePrefix(folder.path, prefix)}>
            <span className="truncate">{folder.name}</span>
          </Link>
        ))}
      </nav>
    </aside>
  )
}

function DashboardToolbar({ payload, pathname, search }: { payload: DashboardPayload; pathname: string; search: string }) {
  const queryClient = useQueryClient()
  const updatePreferences = useMutation({
    mutationFn: updateDashboardPreferences,
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["dashboard"] })
    }
  })
  const sortColumn = sortValue(payload.preferences.sort, "column") || payload.controls.sort_columns[0] || "title"
  const sortDirection = sortValue(payload.preferences.sort, "direction") || payload.controls.sort_directions[0] || "desc"

  function updateSort(next: { column?: string; direction?: string }) {
    updatePreferences.mutate({
      subject: payload.subject,
      sort_column: next.column || sortColumn,
      sort_direction: next.direction || sortDirection
    })
  }

  return (
    <div className="flex flex-wrap items-end justify-between gap-4">
      <div>
        <h2 className="text-lg font-semibold text-gray-900">{capitalize(subjectLabel(payload.subject, 2))}</h2>
        <p className="text-sm text-gray-500">Sorted by {sortColumn || "default"} {sortDirection || "desc"}</p>
        {updatePreferences.isSuccess ? <p className="mt-1 text-sm text-emerald-700" role="status">{updatePreferences.data.message}</p> : null}
        {updatePreferences.isError ? <p className="mt-1 text-sm text-red-700" role="alert">{errorMessage(updatePreferences.error, "Unable to update dashboard preferences.")}</p> : null}
      </div>
      <div className="flex flex-wrap items-end gap-3">
        <nav aria-label="Dashboard view" className="inline-flex overflow-hidden rounded border border-gray-300 bg-white text-sm">
          {payload.controls.views.map((view) => (
            <Link
              className={`px-3 py-1.5 capitalize ${payload.view === view ? "bg-gray-900 text-white" : "text-gray-700 hover:bg-gray-50"}`}
              key={view}
              to={dashboardLinkFromSearch(pathname, search, { view, page: null })}
            >
              {view}
            </Link>
          ))}
        </nav>
        <label className="block text-xs font-medium uppercase text-gray-500" htmlFor="dashboard-sort-column">
          Sort column
          <select
            className="mt-1 block rounded border border-gray-300 bg-white px-2 py-1.5 text-sm normal-case text-gray-700"
            disabled={updatePreferences.isPending}
            id="dashboard-sort-column"
            onChange={(event) => updateSort({ column: event.target.value })}
            value={sortColumn}
          >
            {payload.controls.sort_columns.map((column) => (
              <option key={column} value={column}>{sortColumnLabel(column)}</option>
            ))}
          </select>
        </label>
        <label className="block text-xs font-medium uppercase text-gray-500" htmlFor="dashboard-sort-direction">
          Direction
          <select
            className="mt-1 block rounded border border-gray-300 bg-white px-2 py-1.5 text-sm normal-case text-gray-700"
            disabled={updatePreferences.isPending}
            id="dashboard-sort-direction"
            onChange={(event) => updateSort({ direction: event.target.value })}
            value={sortDirection}
          >
            {payload.controls.sort_directions.map((direction) => (
              <option key={direction} value={direction}>{sortDirectionLabel(direction)}</option>
            ))}
          </select>
        </label>
        {payload.view === "kanban" ? <span className="mb-1 rounded border border-gray-200 bg-gray-50 px-2 py-1 text-xs text-gray-600">Kanban lanes: {payload.preferences.kanban_lanes.join(", ")}</span> : null}
      </div>
    </div>
  )
}

function DashboardTable({ payload }: { payload: DashboardPayload }) {
  if (payload.items.length === 0) {
    return <div className="rounded border border-gray-200 bg-white p-6 text-sm text-gray-500">No {subjectLabel(payload.subject, 2)} match this view.</div>
  }

  if (payload.subject === "job") return <JobsTable items={payload.items.filter((item): item is DashboardJobItem => item.type === "job")} />
  if (payload.subject === "workflow") return <WorkflowsTable items={payload.items.filter((item): item is DashboardWorkflowItem => item.type === "workflow")} />

  return <EpicsTable items={payload.items.filter((item): item is DashboardEpicItem => item.type === "epic")} />
}

function JobsTable({ items }: { items: DashboardJobItem[] }) {
  return (
    <div className="overflow-x-auto rounded border border-gray-200 bg-white">
      <table className="min-w-full divide-y divide-gray-200 text-sm">
        <thead className="bg-gray-50 text-left text-xs font-semibold uppercase text-gray-500">
          <tr>
            <th className="px-4 py-2">Job</th>
            <th className="px-4 py-2">State</th>
            <th className="px-4 py-2">Repository</th>
            <th className="px-4 py-2">Latest</th>
            <th className="px-4 py-2">Updated</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-100">
          {items.map((job) => (
            <tr key={job.id}>
              <td className="max-w-md px-4 py-3">
                <a className="font-medium text-blue-600 hover:underline" href={job.paths.job_path}>{job.title}</a>
                <div className="mt-1 flex flex-wrap gap-1 text-xs text-gray-500">
                  <span>#{job.issue_number || job.id}</span>
                  {job.pr_number ? <span>PR #{job.pr_number}</span> : null}
                  {job.tags.map((tag) => <span className="rounded bg-gray-100 px-1.5 py-0.5" key={tag.id}>{tag.name}</span>)}
                </div>
              </td>
              <td className="px-4 py-3"><StatePill state={job.summary_state} /></td>
              <td className="px-4 py-3 font-mono text-xs text-gray-600">{job.repository.slug}</td>
              <td className="px-4 py-3 text-gray-700">{job.latest_workflow_state}</td>
              <td className="px-4 py-3 text-gray-500">{formatDate(job.updated_at)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

function EpicsTable({ items }: { items: DashboardEpicItem[] }) {
  return (
    <div className="overflow-x-auto rounded border border-gray-200 bg-white">
      <table className="min-w-full divide-y divide-gray-200 text-sm">
        <thead className="bg-gray-50 text-left text-xs font-semibold uppercase text-gray-500">
          <tr>
            <th className="px-4 py-2">Epic</th>
            <th className="px-4 py-2">State</th>
            <th className="px-4 py-2">Repository</th>
            <th className="px-4 py-2">Auto approval</th>
            <th className="px-4 py-2">Updated</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-100">
          {items.map((epic) => (
            <tr key={epic.id}>
              <td className="max-w-md px-4 py-3">
                <a className="font-medium text-blue-600 hover:underline" href={epic.paths.epic_path}>{epic.title}</a>
                <div className="mt-1 font-mono text-xs text-gray-500">{epic.display_number}</div>
              </td>
              <td className="px-4 py-3"><StatePill state={epic.state} /></td>
              <td className="px-4 py-3 font-mono text-xs text-gray-600">{epic.repository.slug}</td>
              <td className="px-4 py-3 text-gray-700">{epic.auto_approve_mode.replace(/_/g, " ")}</td>
              <td className="px-4 py-3 text-gray-500">{formatDate(epic.updated_at)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

function WorkflowsTable({ items }: { items: DashboardWorkflowItem[] }) {
  return (
    <div className="overflow-x-auto rounded border border-gray-200 bg-white">
      <table className="min-w-full divide-y divide-gray-200 text-sm">
        <thead className="bg-gray-50 text-left text-xs font-semibold uppercase text-gray-500">
          <tr>
            <th className="px-4 py-2">Workflow</th>
            <th className="px-4 py-2">State</th>
            <th className="px-4 py-2">Job</th>
            <th className="px-4 py-2">Trigger</th>
            <th className="px-4 py-2">Started</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-100">
          {items.map((workflow) => (
            <tr key={workflow.id}>
              <td className="px-4 py-3 font-medium text-gray-900">Workflow #{workflow.id}</td>
              <td className="px-4 py-3"><StatePill state={workflow.state} /></td>
              <td className="max-w-md px-4 py-3">
                <a className="font-medium text-blue-600 hover:underline" href={workflow.job.path}>{workflow.job.title}</a>
                <div className="mt-1 font-mono text-xs text-gray-500">{workflow.job.repository.slug}</div>
              </td>
              <td className="px-4 py-3 text-gray-700">{workflow.trigger_kind}</td>
              <td className="px-4 py-3 text-gray-500">{formatDate(workflow.started_at || workflow.created_at)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

function Pagination({ payload, pathname, search }: { payload: DashboardPayload; pathname: string; search: string }) {
  if (payload.total_pages <= 1) return null

  const firstItem = (payload.page - 1) * payload.per_page + 1
  const lastItem = Math.min(payload.page * payload.per_page, payload.total)

  return (
    <div className="flex items-center justify-between text-sm text-gray-600">
      <span>Showing {firstItem}-{lastItem} of {payload.total}</span>
      <div className="flex gap-2">
        {payload.page > 1 ? (
          <Link className="rounded border border-gray-300 px-3 py-1 hover:bg-gray-50" to={pageLink(pathname, search, payload.page - 1)}>Previous</Link>
        ) : (
          <span className="rounded border border-gray-200 px-3 py-1 text-gray-300">Previous</span>
        )}
        {payload.page < payload.total_pages ? (
          <Link className="rounded border border-gray-300 px-3 py-1 hover:bg-gray-50" to={pageLink(pathname, search, payload.page + 1)}>Next</Link>
        ) : (
          <span className="rounded border border-gray-200 px-3 py-1 text-gray-300">Next</span>
        )}
      </div>
    </div>
  )
}

function StatePill({ state }: { state: string }) {
  return <span className="inline-flex rounded-full bg-gray-100 px-2 py-0.5 text-xs font-medium capitalize text-gray-700 ring-1 ring-gray-200">{state.replace(/_/g, " ")}</span>
}

function DashboardError({ error }: { error: Error }) {
  return (
    <main aria-label="Dashboard" className="p-6">
      <p className="text-sm text-red-700">{error instanceof ApiError ? error.message : "Unable to load dashboard."}</p>
    </main>
  )
}

function dashboardApiSearch(pathname: string, search: string) {
  const params = new URLSearchParams(search)
  const subject = subjectFromPath(pathname)
  if (subject) params.set("subject", subject)

  const next = params.toString()
  return next ? `?${next}` : ""
}

function subjectFromPath(pathname: string): DashboardSubject | null {
  if (pathname.endsWith("/dashboard/jobs")) return "job"
  if (pathname.endsWith("/dashboard/workflows")) return "workflow"
  if (pathname.endsWith("/dashboard/epics")) return "epic"

  return null
}

function subjectPath(subject: DashboardSubject) {
  if (subject === "job") return "/dashboard/jobs"
  if (subject === "workflow") return "/dashboard/workflows"

  return "/dashboard/epics"
}

function dashboardLink(path: string, params: Record<string, string | number | null | undefined>) {
  const search = new URLSearchParams()
  for (const [key, value] of Object.entries(params)) {
    if (value != null && String(value).length > 0) search.set(key, String(value))
  }

  const query = search.toString()
  return query ? `${path}?${query}` : path
}

function dashboardLinkFromSearch(path: string, search: string, updates: Record<string, string | number | null | undefined>) {
  const params = new URLSearchParams(search)
  for (const [key, value] of Object.entries(updates)) {
    if (value == null || String(value).length === 0) {
      params.delete(key)
    } else {
      params.set(key, String(value))
    }
  }

  const query = params.toString()
  return query ? `${path}?${query}` : path
}

function withRoutePrefix(path: string, prefix: string) {
  if (!prefix || path.startsWith(prefix)) return path
  if (!path.startsWith("/")) return path

  return `${prefix}${path}`
}

function pageLink(pathname: string, search: string, page: number) {
  const params = new URLSearchParams(search)
  params.set("page", String(page))
  const query = params.toString()
  return query ? `${pathname}?${query}` : pathname
}

function folderClass(active: boolean) {
  return `flex min-w-0 rounded px-2 py-1.5 text-sm ${active ? "bg-blue-50 font-medium text-blue-700" : "text-gray-700 hover:bg-gray-100"}`
}

function subjectLabel(subject: DashboardSubject, count: number) {
  const label = subject === "job" ? "job" : subject
  return count === 1 ? label : `${label}s`
}

function sortValue(sort: Record<string, string>, key: string) {
  return sort[key]
}

function sortColumnLabel(column: string) {
  const labels: Record<string, string> = {
    title: "Title",
    state: "State",
    repository: "Repository",
    created_at: "Created",
    updated_at: "Updated",
    started_at: "Started",
    finished_at: "Finished"
  }

  return labels[column] || column.replace(/_/g, " ")
}

function sortDirectionLabel(direction: string) {
  return direction === "asc" ? "Ascending" : "Descending"
}

function capitalize(value: string) {
  return value.charAt(0).toUpperCase() + value.slice(1)
}

function errorMessage(error: Error, fallback: string) {
  return error instanceof ApiError ? error.message : fallback
}

function formatDate(value: string | null) {
  if (!value) return "-"

  return new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(new Date(value))
}
