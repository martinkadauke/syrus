import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"
import { useEffect, useMemo, useState } from "react"
import { Link, useLocation, useNavigate } from "react-router-dom"
import { ApiError } from "../api/client"
import { bulkDashboardJobs, fetchDashboard, toggleDashboardLandingPause, updateDashboardPreferences, type DashboardBulkJobAction, type DashboardEpicItem, type DashboardFilterOption, type DashboardFilterSchemaField, type DashboardItem, type DashboardJobItem, type DashboardLane, type DashboardPayload, type DashboardSubject, type DashboardWorkflowItem } from "../api/dashboard"

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
          <DashboardFilterBar pathname={pathname} search={search} payload={payload} />
          <DashboardTable payload={payload} prefix={prefix} />
          {payload.view === "list" ? <Pagination pathname={pathname} search={search} payload={payload} /> : null}
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
  const queryClient = useQueryClient()
  const landingPause = useMutation({
    mutationFn: () => toggleDashboardLandingPause(payload.landing_queue.toggle_path),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["dashboard"] })
    }
  })

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
      {payload.landing_queue.visible ? (
        <div className="space-y-2 rounded border border-gray-200 bg-white p-2">
          <button
            className="w-full rounded border border-gray-300 px-2 py-1 text-xs font-medium text-gray-700 hover:bg-gray-50 disabled:text-gray-300"
            disabled={landingPause.isPending}
            onClick={() => landingPause.mutate()}
            type="button"
          >
            {payload.landing_queue.paused ? "Resume landing" : "Pause landing"}
          </button>
          {landingPause.isSuccess ? <p className="text-xs text-emerald-700" role="status">{landingPause.data.message}</p> : null}
          {landingPause.isError ? <p className="text-xs text-red-700" role="alert">{errorMessage(landingPause.error, "Unable to update landing queue.")}</p> : null}
        </div>
      ) : null}
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

  function updateLane(lane: string, checked: boolean) {
    const current = payload.preferences.kanban_lanes
    const next = checked ? [ ...current, lane ].filter(uniqueValue) : current.filter((value) => value !== lane)
    updatePreferences.mutate({
      subject: payload.subject,
      kanban_lanes: next
    })
  }

  function updateColumn(column: string, checked: boolean) {
    const optionalColumns = payload.controls.columns.optional.map((option) => option.key)
    const next = optionalColumns.filter((candidate) => {
      if (candidate === column) return checked
      return payload.preferences.visible_columns.includes(candidate)
    })
    updatePreferences.mutate({
      subject: payload.subject,
      visible_columns: next
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
        {payload.view === "list" ? (
          <fieldset className="flex max-w-xl flex-wrap items-center gap-2 rounded border border-gray-200 bg-gray-50 px-2 py-1">
            <legend className="sr-only">Visible columns</legend>
            <span className="mr-1 text-xs font-medium uppercase text-gray-500">Columns</span>
            {payload.controls.columns.optional.map((column) => (
              <label className="inline-flex items-center gap-1 text-xs text-gray-700" key={column.key}>
                <input
                  checked={payload.preferences.visible_columns.includes(column.key)}
                  disabled={updatePreferences.isPending}
                  onChange={(event) => updateColumn(column.key, event.target.checked)}
                  type="checkbox"
                />
                <span>{column.title}</span>
              </label>
            ))}
          </fieldset>
        ) : null}
        {payload.view === "kanban" ? (
          <fieldset className="flex max-w-xl flex-wrap items-center gap-2 rounded border border-gray-200 bg-gray-50 px-2 py-1">
            <legend className="sr-only">Kanban lanes</legend>
            <span className="mr-1 text-xs font-medium uppercase text-gray-500">Lanes</span>
            {payload.controls.kanban_lanes.map((lane) => (
              <label className="inline-flex items-center gap-1 text-xs text-gray-700" key={lane.key}>
                <input
                  checked={payload.preferences.kanban_lanes.includes(lane.key)}
                  disabled={updatePreferences.isPending}
                  onChange={(event) => updateLane(lane.key, event.target.checked)}
                  type="checkbox"
                />
                <span>{lane.title}</span>
              </label>
            ))}
          </fieldset>
        ) : null}
      </div>
    </div>
  )
}

function DashboardFilterBar({ payload, pathname, search }: { payload: DashboardPayload; pathname: string; search: string }) {
  const navigate = useNavigate()
  const controls = filterControlsFor(payload)
  if (controls.length === 0) return null

  const params = new URLSearchParams(search)
  const activeControls = controls.filter((control) => params.get(control.param))
  const hasFilters = activeControls.length > 0 || params.has("q") || params.has("smart_folder_id")

  function changeFilter(param: string, value: string) {
    navigate(dashboardLinkFromSearch(pathname, search, { [param]: value || null, page: null }))
  }

  return (
    <div className="space-y-2 rounded border border-gray-200 bg-white p-3">
      <div className="flex flex-wrap items-end gap-3">
        {controls.map((control) => (
          <label className="block text-xs font-medium uppercase text-gray-500" htmlFor={`dashboard-filter-${control.param}`} key={control.param}>
            {control.label}
            <select
              className="mt-1 block rounded border border-gray-300 bg-white px-2 py-1.5 text-sm normal-case text-gray-700"
              id={`dashboard-filter-${control.param}`}
              onChange={(event) => changeFilter(control.param, event.target.value)}
              value={params.get(control.param) || ""}
            >
              <option value="">All</option>
              {control.options.map((option) => (
                <option key={String(option.value)} value={String(option.value)}>{option.label}</option>
              ))}
            </select>
          </label>
        ))}
        {hasFilters ? (
          <Link className="mb-1 text-sm text-gray-500 underline hover:text-gray-700" to={clearFiltersLink(pathname, search)}>
            Clear filters
          </Link>
        ) : null}
      </div>

      {activeControls.length > 0 ? (
        <div className="flex flex-wrap gap-2 text-xs">
          {activeControls.map((control) => (
            <span className="rounded bg-blue-50 px-2 py-1 text-blue-700" key={control.param}>
              {control.label}: {optionLabel(control.options, params.get(control.param) || "")}
            </span>
          ))}
        </div>
      ) : null}
    </div>
  )
}

function DashboardTable({ payload, prefix }: { payload: DashboardPayload; prefix: string }) {
  if (payload.view === "kanban") return <DashboardKanban payload={payload} prefix={prefix} />

  if (payload.items.length === 0) {
    return <div className="rounded border border-gray-200 bg-white p-6 text-sm text-gray-500">No {subjectLabel(payload.subject, 2)} match this view.</div>
  }

  const columns = dashboardVisibleColumns(payload)
  if (payload.subject === "job") return <JobsDashboardTable columns={columns} items={payload.items.filter((item): item is DashboardJobItem => item.type === "job")} prefix={prefix} />
  if (payload.subject === "workflow") return <WorkflowsTable columns={columns} items={payload.items.filter((item): item is DashboardWorkflowItem => item.type === "workflow")} prefix={prefix} />

  return <EpicsTable columns={columns} items={payload.items.filter((item): item is DashboardEpicItem => item.type === "epic")} prefix={prefix} />
}

function DashboardKanban({ payload, prefix }: { payload: DashboardPayload; prefix: string }) {
  if (payload.lanes.length === 0) {
    return <div className="rounded border border-gray-200 bg-white p-6 text-sm text-gray-500">No kanban lanes are configured.</div>
  }

  return (
    <div className="overflow-x-auto pb-2">
      <div className="grid min-w-[56rem] gap-3" style={{ gridTemplateColumns: `repeat(${payload.lanes.length}, minmax(14rem, 1fr))` }}>
        {payload.lanes.map((lane) => (
          <KanbanLane key={lane.key} lane={lane} prefix={prefix} subject={payload.subject} />
        ))}
      </div>
    </div>
  )
}

function KanbanLane({ lane, prefix, subject }: { lane: DashboardLane; prefix: string; subject: DashboardSubject }) {
  return (
    <section className="min-h-64 rounded border border-gray-200 bg-gray-50">
      <header className="flex items-center justify-between border-b border-gray-200 px-3 py-2">
        <h3 className="text-sm font-semibold text-gray-900">{lane.title}</h3>
        <span className="rounded bg-white px-2 py-0.5 text-xs text-gray-500 ring-1 ring-gray-200">{lane.count}</span>
      </header>
      <div className="space-y-2 p-2">
        {lane.items.length === 0 ? <p className="px-1 py-2 text-sm text-gray-400">No {subjectLabel(subject, 2)}</p> : null}
        {lane.items.map((item) => <KanbanCard item={item} key={`${item.type}-${item.id}`} prefix={prefix} />)}
      </div>
    </section>
  )
}

function KanbanCard({ item, prefix }: { item: DashboardItem; prefix: string }) {
  if (item.type === "job") {
    return (
      <article className="rounded border border-gray-200 bg-white p-3 shadow-sm">
        <Link className="text-sm font-medium text-blue-600 hover:underline" to={withRoutePrefix(item.paths.job_path, prefix)}>{item.title}</Link>
        <div className="mt-2 flex flex-wrap gap-1 text-xs text-gray-500">
          <StatePill state={item.summary_state} />
          <span className="rounded bg-gray-100 px-1.5 py-0.5">{item.repository.slug}</span>
          {item.pr_number ? <span className="rounded bg-gray-100 px-1.5 py-0.5">PR #{item.pr_number}</span> : null}
        </div>
      </article>
    )
  }

  if (item.type === "workflow") {
    return (
      <article className="rounded border border-gray-200 bg-white p-3 shadow-sm">
        <div className="text-sm font-medium text-gray-900">Workflow #{item.id}</div>
        <Link className="mt-1 block text-sm text-blue-600 hover:underline" to={withRoutePrefix(item.job.path, prefix)}>{item.job.title}</Link>
        <div className="mt-2 flex flex-wrap gap-1 text-xs text-gray-500">
          <StatePill state={item.state} />
          <span className="rounded bg-gray-100 px-1.5 py-0.5">{item.trigger_kind}</span>
        </div>
      </article>
    )
  }

  return (
    <article className="rounded border border-gray-200 bg-white p-3 shadow-sm">
      <Link className="text-sm font-medium text-blue-600 hover:underline" to={withRoutePrefix(item.paths.epic_path, prefix)}>{item.title}</Link>
      <div className="mt-2 flex flex-wrap gap-1 text-xs text-gray-500">
        <StatePill state={item.state} />
        <span className="rounded bg-gray-100 px-1.5 py-0.5">{item.repository.slug}</span>
      </div>
    </article>
  )
}

function JobsDashboardTable({ items, columns, prefix }: { items: DashboardJobItem[]; columns: string[]; prefix: string }) {
  const [selectedIds, setSelectedIds] = useState<Set<number>>(() => new Set())
  const visibleIds = useMemo(() => items.map((item) => item.id), [items])
  const selectedArray = useMemo(() => Array.from(selectedIds), [selectedIds])
  const allSelected = visibleIds.length > 0 && visibleIds.every((id) => selectedIds.has(id))

  useEffect(() => {
    setSelectedIds((current) => {
      const visible = new Set(visibleIds)
      const next = new Set(Array.from(current).filter((id) => visible.has(id)))
      return next.size === current.size ? current : next
    })
  }, [visibleIds])

  function toggleAll() {
    setSelectedIds((current) => {
      if (allSelected) return new Set()
      return new Set([ ...Array.from(current), ...visibleIds ])
    })
  }

  function toggleOne(id: number) {
    setSelectedIds((current) => {
      const next = new Set(current)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  return (
    <div className="space-y-3">
      <BulkJobActions selectedIds={selectedArray} onClear={() => setSelectedIds(new Set())} />
      <JobsTable
        allSelected={allSelected}
        columns={columns}
        items={items}
        onToggleAll={toggleAll}
        onToggleOne={toggleOne}
        prefix={prefix}
        selectedIds={selectedIds}
      />
    </div>
  )
}

function BulkJobActions({ selectedIds, onClear }: { selectedIds: number[]; onClear: () => void }) {
  const queryClient = useQueryClient()
  const [notice, setNotice] = useState<string | null>(null)
  const action = useMutation({
    mutationFn: (bulkAction: DashboardBulkJobAction) => bulkDashboardJobs({ job_ids: selectedIds, bulk_action: bulkAction }),
    onSuccess: (payload) => {
      setNotice(payload.message)
      onClear()
      void queryClient.invalidateQueries({ queryKey: ["dashboard"] })
    }
  })
  const disabled = selectedIds.length === 0 || action.isPending

  function run(bulkAction: DashboardBulkJobAction) {
    setNotice(null)
    if (bulkAction === "close" && !window.confirm(`Close ${selectedIds.length} selected job${selectedIds.length === 1 ? "" : "s"}?`)) return
    action.mutate(bulkAction)
  }

  return (
    <div className="flex flex-wrap items-center justify-between gap-3 rounded border border-gray-200 bg-gray-50 px-3 py-2 text-sm">
      <div>
        <span className="font-medium text-gray-900">{selectedIds.length}</span>
        <span className="text-gray-600"> selected</span>
        {notice ? <span className="ml-3 text-emerald-700" role="status">{notice}</span> : null}
        {action.isError ? <span className="ml-3 text-red-700" role="alert">{errorMessage(action.error, "Bulk action failed.")}</span> : null}
      </div>
      <div className="flex flex-wrap gap-2">
        <button className={bulkButtonClass(disabled)} disabled={disabled} onClick={() => run("retry")} type="button">Retry</button>
        <button className={bulkButtonClass(disabled)} disabled={disabled} onClick={() => run("approve")} type="button">Approve</button>
        <button className={bulkButtonClass(disabled, "danger")} disabled={disabled} onClick={() => run("close")} type="button">Close</button>
      </div>
    </div>
  )
}

function JobsTable({
  items,
  columns,
  selectedIds,
  allSelected,
  onToggleAll,
  onToggleOne,
  prefix
}: {
  items: DashboardJobItem[]
  columns: string[]
  selectedIds: Set<number>
  allSelected: boolean
  onToggleAll: () => void
  onToggleOne: (id: number) => void
  prefix: string
}) {
  return (
    <div className="overflow-x-auto rounded border border-gray-200 bg-white">
      <table className="min-w-full divide-y divide-gray-200 text-sm">
        <thead className="bg-gray-50 text-left text-xs font-semibold uppercase text-gray-500">
          <tr>
            {columns.map((column) => (
              <th className={column === "checkbox" ? "w-10 px-4 py-2" : "px-4 py-2"} key={column}>
                {column === "checkbox" ? <input aria-label="Select all jobs" checked={allSelected} onChange={onToggleAll} type="checkbox" /> : dashboardColumnLabel("job", column)}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-100">
          {items.map((job) => (
            <tr key={job.id}>
              {columns.map((column) => <JobCell column={column} job={job} key={column} onToggleOne={onToggleOne} prefix={prefix} selected={selectedIds.has(job.id)} />)}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

function JobCell({ job, column, selected, onToggleOne, prefix }: { job: DashboardJobItem; column: string; selected: boolean; onToggleOne: (id: number) => void; prefix: string }) {
  if (column === "checkbox") {
    return <td className="px-4 py-3 align-top"><input aria-label={`Select ${job.title}`} checked={selected} onChange={() => onToggleOne(job.id)} type="checkbox" /></td>
  }
  if (column === "issue" || column === "title") {
    return (
      <td className="max-w-md px-4 py-3">
        <Link className="font-medium text-blue-600 hover:underline" to={withRoutePrefix(job.paths.job_path, prefix)}>{job.title}</Link>
        <div className="mt-1 flex flex-wrap gap-1 text-xs text-gray-500">
          <span>#{job.issue_number || job.id}</span>
          {job.pr_number ? <span>PR #{job.pr_number}</span> : null}
          {job.tags.map((tag) => <span className="rounded bg-gray-100 px-1.5 py-0.5" key={tag.id}>{tag.name}</span>)}
        </div>
      </td>
    )
  }
  if (column === "state") return <td className="px-4 py-3"><StatePill state={job.summary_state} /></td>
  if (column === "repository") return <td className="px-4 py-3 font-mono text-xs text-gray-600">{job.repository.slug}</td>
  if (column === "latest") return <td className="px-4 py-3 text-gray-700">{job.latest_workflow_state}</td>
  if (column === "workflows_count") return <td className="px-4 py-3 text-gray-700">{job.workflows_count}</td>

  return <td className="px-4 py-3 text-gray-500">{formatDate(jobDateValue(job, column))}</td>
}

function EpicsTable({ items, columns, prefix }: { items: DashboardEpicItem[]; columns: string[]; prefix: string }) {
  return (
    <div className="overflow-x-auto rounded border border-gray-200 bg-white">
      <table className="min-w-full divide-y divide-gray-200 text-sm">
        <thead className="bg-gray-50 text-left text-xs font-semibold uppercase text-gray-500">
          <tr>
            {columns.map((column) => <th className="px-4 py-2" key={column}>{dashboardColumnLabel("epic", column)}</th>)}
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-100">
          {items.map((epic) => (
            <tr key={epic.id}>
              {columns.map((column) => <EpicCell column={column} epic={epic} key={column} prefix={prefix} />)}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

function EpicCell({ epic, column, prefix }: { epic: DashboardEpicItem; column: string; prefix: string }) {
  if (column === "epic") {
    return (
      <td className="max-w-md px-4 py-3">
        <Link className="font-medium text-blue-600 hover:underline" to={withRoutePrefix(epic.paths.epic_path, prefix)}>{epic.title}</Link>
        <div className="mt-1 font-mono text-xs text-gray-500">{epic.display_number}</div>
      </td>
    )
  }
  if (column === "state") return <td className="px-4 py-3"><StatePill state={epic.state} /></td>
  if (column === "repository") return <td className="px-4 py-3 font-mono text-xs text-gray-600">{epic.repository.slug}</td>
  if (column === "updated") return <td className="px-4 py-3 text-gray-500">{formatDate(epic.updated_at)}</td>

  return <td className="px-4 py-3 text-gray-500">{formatDate(epicDateValue(epic, column))}</td>
}

function WorkflowsTable({ items, columns, prefix }: { items: DashboardWorkflowItem[]; columns: string[]; prefix: string }) {
  return (
    <div className="overflow-x-auto rounded border border-gray-200 bg-white">
      <table className="min-w-full divide-y divide-gray-200 text-sm">
        <thead className="bg-gray-50 text-left text-xs font-semibold uppercase text-gray-500">
          <tr>
            {columns.map((column) => <th className="px-4 py-2" key={column}>{dashboardColumnLabel("workflow", column)}</th>)}
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-100">
          {items.map((workflow) => (
            <tr key={workflow.id}>
              {columns.map((column) => <WorkflowCell column={column} key={column} prefix={prefix} workflow={workflow} />)}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

function WorkflowCell({ workflow, column, prefix }: { workflow: DashboardWorkflowItem; column: string; prefix: string }) {
  if (column === "workflow" || column === "title") return <td className="px-4 py-3 font-medium text-gray-900">Workflow #{workflow.id}</td>
  if (column === "state") return <td className="px-4 py-3"><StatePill state={workflow.state} /></td>
  if (column === "job") {
    return (
      <td className="max-w-md px-4 py-3">
        <Link className="font-medium text-blue-600 hover:underline" to={withRoutePrefix(workflow.job.path, prefix)}>{workflow.job.title}</Link>
        <div className="mt-1 font-mono text-xs text-gray-500">{workflow.job.repository.slug}</div>
      </td>
    )
  }
  if (column === "trigger") return <td className="px-4 py-3 text-gray-700">{workflow.trigger_kind}</td>
  if (column === "agent") return <td className="px-4 py-3 text-gray-700">{workflow.agent_provider}</td>
  if (column === "started") return <td className="px-4 py-3 text-gray-500">{formatDate(workflow.started_at || workflow.created_at)}</td>
  if (column === "finished") return <td className="px-4 py-3 text-gray-500">{formatDate(workflow.finished_at)}</td>

  return <td className="px-4 py-3 text-gray-500">{formatDate(workflowDateValue(workflow, column))}</td>
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

function clearFiltersLink(path: string, search: string) {
  const params = new URLSearchParams(search)
  for (const key of ["state", "repository_id", "kind", "trigger_kind", "job_id", "attention", "tag_ids", "pr", "age", "q", "smart_folder_id", "page"]) {
    params.delete(key)
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

function bulkButtonClass(disabled: boolean, tone: "default" | "danger" = "default") {
  if (disabled) return "rounded border border-gray-200 px-3 py-1 text-gray-300"
  if (tone === "danger") return "rounded border border-red-300 px-3 py-1 text-red-700 hover:bg-red-50"

  return "rounded border border-gray-300 px-3 py-1 text-gray-700 hover:bg-white"
}

function uniqueValue(value: string, index: number, values: string[]) {
  return values.indexOf(value) === index
}

function filterControlsFor(payload: DashboardPayload) {
  const controls: Array<{ param: string; label: string; options: DashboardFilterOption[] }> = []
  const state = schemaField(payload.controls.filter_schema, "state")
  const repository = schemaField(payload.controls.filter_schema, "repository_id")
  const kind = payload.subject === "job" ? schemaField(payload.controls.filter_schema, "kind") : null
  const triggerKind = payload.subject === "workflow" ? schemaField(payload.controls.filter_schema, "trigger_kind") : null

  if (state) controls.push({ param: "state", label: state.label, options: normalizedOptions(state) })
  if (repository) controls.push({ param: "repository_id", label: repository.label, options: normalizedOptions(repository) })
  if (kind) controls.push({ param: "kind", label: kind.label, options: normalizedOptions(kind) })
  if (triggerKind) controls.push({ param: "trigger_kind", label: triggerKind.label, options: normalizedOptions(triggerKind) })

  return controls.filter((control) => control.options.length > 0)
}

function schemaField(schema: DashboardFilterSchemaField[], field: string) {
  return schema.find((candidate) => candidate.field === field) || null
}

function normalizedOptions(field: DashboardFilterSchemaField): DashboardFilterOption[] {
  return (field.values || []).map((option) => {
    if (typeof option === "string") return { value: option, label: humanizeOption(option) }
    return option
  })
}

function optionLabel(options: DashboardFilterOption[], value: string) {
  return options.find((option) => String(option.value) === value)?.label || value
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

function dashboardColumnLabel(subject: DashboardSubject, column: string) {
  const labels: Record<DashboardSubject, Record<string, string>> = {
    epic: {
      epic: "Epic",
      state: "State",
      repository: "Repository",
      updated: "Updated",
      created_at: "Created at",
      updated_at: "Updated at",
      done_at: "Done at",
      archived_at: "Archived at"
    },
    job: {
      checkbox: "Checkbox",
      issue: "Issue",
      title: "Title",
      state: "State",
      repository: "Repository",
      latest: "Latest",
      workflows_count: "Workflows count",
      started: "Started",
      created_at: "Created at",
      updated_at: "Updated at",
      started_at: "Started at",
      finished_at: "Finished at",
      approved_at: "Approved at",
      dependencies_overridden_at: "Dependencies overridden at",
      last_feedback_addressed_at: "Last feedback addressed at",
      last_seen_comment_at: "Last seen comment at",
      pr_mergeable_checked_at: "PR mergeable checked at"
    },
    workflow: {
      workflow: "Workflow",
      title: "Workflow",
      job: "Job",
      trigger: "Trigger",
      state: "State",
      started: "Started",
      finished: "Finished",
      agent: "Agent",
      created_at: "Created at",
      updated_at: "Updated at",
      started_at: "Started at",
      finished_at: "Finished at",
      cleaned_up_at: "Cleaned up at"
    }
  }

  return labels[subject][column] || humanizeOption(column)
}

function dashboardVisibleColumns(payload: DashboardPayload) {
  const allowed = new Set([
    ...payload.controls.columns.required.map((column) => column.key),
    ...payload.controls.columns.optional.map((column) => column.key)
  ])
  const normalized = [
    ...payload.controls.columns.required.map((column) => column.key),
    ...payload.preferences.visible_columns.map((column) => normalizeDashboardColumn(payload.subject, column))
  ]

  return normalized.filter((column, index, columns) => allowed.has(column) && columns.indexOf(column) === index)
}

function normalizeDashboardColumn(subject: DashboardSubject, column: string) {
  if (subject === "job" && column === "title") return "issue"
  if (subject === "workflow" && column === "title") return "workflow"

  return column
}

function jobDateValue(job: DashboardJobItem, column: string) {
  const values: Record<string, string | null> = {
    started: job.started_at,
    created_at: job.created_at,
    updated_at: job.updated_at,
    started_at: job.started_at,
    finished_at: job.finished_at,
    approved_at: job.approved_at,
    dependencies_overridden_at: job.dependencies_overridden_at,
    last_feedback_addressed_at: job.last_feedback_addressed_at,
    last_seen_comment_at: job.last_seen_comment_at,
    pr_mergeable_checked_at: job.pr_mergeable_checked_at
  }

  return values[column] || null
}

function epicDateValue(epic: DashboardEpicItem, column: string) {
  const values: Record<string, string | null> = {
    created_at: epic.created_at,
    updated_at: epic.updated_at,
    done_at: epic.done_at,
    archived_at: epic.archived_at
  }

  return values[column] || null
}

function workflowDateValue(workflow: DashboardWorkflowItem, column: string) {
  const values: Record<string, string | null> = {
    created_at: workflow.created_at,
    updated_at: workflow.updated_at,
    started_at: workflow.started_at,
    finished_at: workflow.finished_at,
    cleaned_up_at: workflow.cleaned_up_at
  }

  return values[column] || null
}

function humanizeOption(value: string) {
  return value.replace(/_/g, " ").replace(/^\w/, (match) => match.toUpperCase())
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
