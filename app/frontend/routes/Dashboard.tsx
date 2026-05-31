import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"
import type { FormEvent, RefObject } from "react"
import { useEffect, useMemo, useRef, useState } from "react"
import { Link, useLocation, useNavigate } from "react-router-dom"
import { ApiError } from "../api/client"
import { bulkDashboardJobs, createDashboardSmartFolder, fetchDashboard, toggleDashboardLandingPause, updateDashboardPreferences, type DashboardBulkJobAction, type DashboardEpicItem, type DashboardFilterOption, type DashboardFilterSchemaField, type DashboardItem, type DashboardJobItem, type DashboardLane, type DashboardPayload, type DashboardSmartFolder, type DashboardSubject, type DashboardWorkflowItem } from "../api/dashboard"

export function DashboardRoute() {
  const location = useLocation()
  const search = dashboardApiSearch(location.pathname, location.search)
  const dashboard = useQuery({
    queryKey: ["dashboard", search],
    queryFn: () => fetchDashboard(search),
    placeholderData: (previousData) => previousData
  })

  if (dashboard.isPending) return <main aria-label="Dashboard" className="p-6 text-sm text-gray-600">Loading...</main>
  if (dashboard.isError) return <DashboardError error={dashboard.error} />

  return <DashboardView pathname={location.pathname} search={location.search} payload={dashboard.data} />
}

function DashboardView({ payload, pathname, search }: { payload: DashboardPayload; pathname: string; search: string }) {
  const prefix = pathname.startsWith("/app-shell") ? "/app-shell" : ""

  return (
    <main aria-label="Dashboard" className="mx-auto max-w-7xl space-y-5 p-6">
      <header className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-3xl font-semibold text-gray-900">Dashboard</h1>
        <DashboardCreateActions payload={payload} prefix={prefix} />
      </header>

      <div className="grid gap-5 lg:grid-cols-[16rem_minmax(0,1fr)] lg:items-center">
        <SubjectTabs payload={payload} prefix={prefix} />
        <div className="flex min-w-0 flex-col gap-3 lg:flex-row lg:items-center">
          <div className="min-w-0 flex-1">
            <DashboardFilterBar pathname={pathname} search={search} payload={payload} />
          </div>
          <DashboardToolbar pathname={pathname} search={search} payload={payload} />
        </div>
      </div>

      <div className="grid gap-5 lg:grid-cols-[16rem_minmax(0,1fr)]">
        <SmartFolderNav payload={payload} prefix={prefix} search={search} />
        <section className="min-w-0 space-y-4">
          <DashboardTable payload={payload} prefix={prefix} />
          {payload.view === "list" ? <Pagination pathname={pathname} search={search} payload={payload} /> : null}
        </section>
      </div>
    </main>
  )
}

function DashboardCreateActions({ payload, prefix }: { payload: DashboardPayload; prefix: string }) {
  return (
    <div className="flex flex-wrap gap-2">
      <Link className="rounded border border-gray-300 bg-white px-3 py-1.5 text-sm font-medium text-gray-700 hover:bg-gray-50" to={withRoutePrefix(payload.paths.new_epic_path, prefix)}>New Epic</Link>
      <Link className="rounded bg-gray-900 px-3 py-1.5 text-sm font-medium text-white hover:bg-gray-700" to={withRoutePrefix(payload.paths.new_job_path, prefix)}>New Job</Link>
    </div>
  )
}

function SubjectTabs({ payload, prefix }: { payload: DashboardPayload; prefix: string }) {
  const subjects: Array<{ key: DashboardSubject; label: string; path: string }> = [
    { key: "epic", label: "Epics", path: "/dashboard/epics" },
    { key: "job", label: "Jobs", path: "/dashboard/jobs" },
    { key: "workflow", label: "Workflows", path: "/dashboard/workflows" }
  ]

  return (
    <nav aria-label="Dashboard subjects" className="flex flex-wrap gap-2">
      {subjects.map((subject) => (
        <Link
          className={`rounded border px-3 py-1.5 text-sm font-medium ${payload.subject === subject.key ? "border-blue-600 bg-blue-50 text-blue-700" : "border-gray-300 bg-white text-gray-700 hover:bg-gray-50"}`}
          key={subject.key}
          to={dashboardLink(`${prefix}${subject.path}`, { view: payload.view })}
        >
          {subject.label}
        </Link>
      ))}
    </nav>
  )
}

function SmartFolderNav({ payload, prefix, search }: { payload: DashboardPayload; prefix: string; search: string }) {
  const queryClient = useQueryClient()
  const navigate = useNavigate()
  const [folderName, setFolderName] = useState("")
  const builtinFolders = payload.smart_folders.filter((folder) => folder.kind !== "user_defined")
  const primaryFolders = builtinFolders.filter((folder) => folder.visibility !== "on_demand")
  const moreFolders = builtinFolders.filter((folder) => folder.visibility === "on_demand")
  const savedFolders = payload.smart_folders.filter((folder) => folder.kind === "user_defined")
  const appliedTree = filterTreeFromPayload(payload.filter)
  const canSaveFilter = topFilterChildren(appliedTree).length > 0
  const landingPause = useMutation({
    mutationFn: () => toggleDashboardLandingPause(payload.landing_queue.toggle_path),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["dashboard"] })
    }
  })
  const createFolder = useMutation({
    mutationFn: () => createDashboardSmartFolder({
      subject: payload.subject,
      name: folderName,
      filters: smartFolderFiltersFromTree(appliedTree)
    }),
    onSuccess: (created) => {
      setFolderName("")
      void queryClient.invalidateQueries({ queryKey: ["dashboard"] })
      navigate(withRoutePrefix(created.redirect_to, prefix))
    }
  })

  function saveFolder(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    createFolder.mutate()
  }

  return (
    <aside aria-label="Dashboard smart folders panel" className="space-y-2">
      <h2 className="text-xs font-semibold uppercase text-gray-500">Smart folders</h2>
      <nav aria-label="Dashboard smart folders" className="space-y-1">
        <Link className={folderClass(payload.active_smart_folder_id == null)} to={dashboardLink(`${prefix}${subjectPath(payload.subject)}`, { view: payload.view })}>
          All {subjectLabel(payload.subject, 2)}
        </Link>
        {primaryFolders.map((folder) => <SmartFolderLink folder={folder} key={folder.id} prefix={prefix} />)}
        {moreFolders.length > 0 ? (
          <details className="space-y-1" open={moreFolders.some((folder) => folder.active) || undefined}>
            <summary className="cursor-pointer rounded px-2 py-1.5 text-sm font-medium text-gray-600 hover:bg-gray-100">More</summary>
            <div className="space-y-1 pl-2">
              {moreFolders.map((folder) => <SmartFolderLink folder={folder} key={folder.id} prefix={prefix} />)}
            </div>
          </details>
        ) : null}
      </nav>
      <div className="space-y-1 pt-3">
        <div className="flex items-center justify-between gap-2 px-2">
          <h3 className="text-xs font-semibold uppercase text-gray-500">Saved</h3>
          <Link className="text-xs font-medium text-blue-700 hover:text-blue-900" to={withRoutePrefix(`/smart_folders?subject_type=${payload.subject}`, prefix)}>Manage</Link>
        </div>
        {savedFolders.length > 0 ? (
          <nav aria-label="Saved smart folders" className="space-y-1">
            {savedFolders.map((folder) => <SmartFolderLink folder={folder} key={folder.id} prefix={prefix} />)}
          </nav>
        ) : (
          <p className="px-2 py-1.5 text-sm text-gray-400">No saved folders</p>
        )}
      </div>
      {canSaveFilter ? (
        <form className="space-y-2 px-2 pt-3" onSubmit={saveFolder}>
          <label className="block text-xs font-medium uppercase text-gray-500" htmlFor="dashboard-smart-folder-name">
            Folder name
            <input
              className="mt-1 block w-full rounded border border-gray-300 bg-white px-2 py-1.5 text-sm normal-case text-gray-700"
              disabled={createFolder.isPending}
              id="dashboard-smart-folder-name"
              maxLength={120}
              onChange={(event) => setFolderName(event.target.value)}
              required
              type="text"
              value={folderName}
            />
          </label>
          <button className="w-full rounded bg-blue-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-blue-500 disabled:bg-gray-300" disabled={createFolder.isPending} type="submit">
            Save folder
          </button>
          {createFolder.isError ? <p className="text-xs text-red-700" role="alert">{errorMessage(createFolder.error, "Unable to save smart folder.")}</p> : null}
        </form>
      ) : null}
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

function SmartFolderLink({ folder, prefix }: { folder: DashboardSmartFolder; prefix: string }) {
  return (
    <Link aria-label={`${folder.name} ${folder.count}`} className={folderClass(folder.active)} to={withRoutePrefix(folder.path, prefix)}>
      <span className="truncate">{folder.name}</span>
      <span className={`ml-auto inline-flex min-w-6 justify-center rounded-full px-1.5 py-0.5 text-xs ${folder.active ? "bg-blue-100 text-blue-700" : "bg-gray-100 text-gray-600"}`}>{folder.count}</span>
    </Link>
  )
}

function DashboardToolbar({ payload, pathname, search }: { payload: DashboardPayload; pathname: string; search: string }) {
  const queryClient = useQueryClient()
  const [columnsOpen, setColumnsOpen] = useState(false)
  const [lanesOpen, setLanesOpen] = useState(false)
  const columnsMenuRef = useRef<HTMLDivElement>(null)
  const lanesMenuRef = useRef<HTMLDivElement>(null)
  const updatePreferences = useMutation({
    mutationFn: updateDashboardPreferences,
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["dashboard"] })
    }
  })

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

  useEffect(() => {
    if (!columnsOpen && !lanesOpen) return

    function closeOnEscape(event: KeyboardEvent) {
      if (event.key !== "Escape") return

      setColumnsOpen(false)
      setLanesOpen(false)
    }

    function closeOnOutsidePointer(event: PointerEvent) {
      const target = event.target
      if (target instanceof Node) {
        if (columnsOpen && columnsMenuRef.current?.contains(target)) return
        if (lanesOpen && lanesMenuRef.current?.contains(target)) return
      }

      setColumnsOpen(false)
      setLanesOpen(false)
    }

    window.addEventListener("keydown", closeOnEscape)
    window.addEventListener("pointerdown", closeOnOutsidePointer)
    return () => {
      window.removeEventListener("keydown", closeOnEscape)
      window.removeEventListener("pointerdown", closeOnOutsidePointer)
    }
  }, [columnsOpen, lanesOpen])

  return (
    <div className="shrink-0">
      <div className="flex flex-wrap items-center justify-end gap-3">
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
        {payload.view === "list" ? (
          <div className="relative" ref={columnsMenuRef}>
            <button
              aria-label="Columns"
              aria-controls="dashboard-columns-menu"
              aria-expanded={columnsOpen}
              aria-haspopup="menu"
              className="inline-flex h-9 w-9 items-center justify-center rounded border border-gray-300 bg-white text-gray-700 hover:bg-gray-50"
              onClick={() => setColumnsOpen((open) => !open)}
              type="button"
            >
              <ColumnsIcon />
            </button>
            {columnsOpen ? (
              <div className="absolute right-0 z-20 mt-2 w-64 rounded border border-gray-200 bg-white p-3 shadow-lg" id="dashboard-columns-menu" role="menu">
                <fieldset className="space-y-2">
                  <legend className="text-xs font-semibold uppercase text-gray-500">Visible columns</legend>
                  {payload.controls.columns.optional.map((column) => (
                    <label className="flex items-center gap-2 text-sm text-gray-700" key={column.key}>
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
              </div>
            ) : null}
          </div>
        ) : null}
        {payload.view === "kanban" ? (
          <div className="relative" ref={lanesMenuRef}>
            <button
              aria-label="Kanban lanes"
              aria-controls="dashboard-kanban-lanes-menu"
              aria-expanded={lanesOpen}
              aria-haspopup="menu"
              className="inline-flex h-9 w-9 items-center justify-center rounded border border-gray-300 bg-white text-gray-700 hover:bg-gray-50"
              onClick={() => setLanesOpen((open) => !open)}
              type="button"
            >
              <ColumnsIcon />
            </button>
            {lanesOpen ? (
              <div className="absolute right-0 z-20 mt-2 w-64 rounded border border-gray-200 bg-white p-3 shadow-lg" id="dashboard-kanban-lanes-menu" role="menu">
                <fieldset className="space-y-2">
                  <legend className="text-xs font-semibold uppercase text-gray-500">Kanban lanes</legend>
                  {payload.controls.kanban_lanes.map((lane) => (
                    <label className="flex items-center gap-2 text-sm text-gray-700" key={lane.key}>
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
              </div>
            ) : null}
          </div>
        ) : null}
      </div>
      {updatePreferences.isError ? <p className="mt-1 text-right text-sm text-red-700" role="alert">{errorMessage(updatePreferences.error, "Unable to update dashboard preferences.")}</p> : null}
    </div>
  )
}

function ColumnsIcon() {
  return (
    <svg aria-hidden="true" className="h-5 w-5" fill="none" viewBox="0 0 24 24">
      <path d="M7 4v16M17 4v16M5 5h14M5 12h14M5 19h14" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" />
    </svg>
  )
}

function DashboardFilterBar({ payload, pathname, search }: { payload: DashboardPayload; pathname: string; search: string }) {
  const navigate = useNavigate()
  const [draftTree, setDraftTree] = useState<FilterTree>(() => filterTreeFromPayload(payload.filter))
  const [editingPath, setEditingPath] = useState<FilterPath | null>(null)
  const [addMenuOpen, setAddMenuOpen] = useState(false)
  const [addQuery, setAddQuery] = useState("")
  const [pendingAddTarget, setPendingAddTarget] = useState<PendingAddTarget>({ kind: "and" })
  const addMenuRef = useRef<HTMLDivElement | null>(null)
  const editorRef = useRef<HTMLDivElement>(null)
  const controls = payload.controls.filter_schema
  const params = new URLSearchParams(search)
  const appliedTree = useMemo(() => filterTreeFromPayload(payload.filter), [payload.filter])
  const draftChildren = topFilterChildren(draftTree)
  const hasFilters = draftChildren.length > 0 || legacyFilterKeys.some((key) => params.has(key)) || params.has("smart_folder_id")
  const filteredControls = controls.filter((control) => {
    const query = addQuery.trim().toLowerCase()
    return !query || control.field.toLowerCase().includes(query) || control.label.toLowerCase().includes(query)
  })
  const editingChip = editingPath ? filterNodeAtPath(draftTree, editingPath) : null
  const editingMeta = editingChip && "field" in editingChip ? filterMetaFor(controls, editingChip.field) : null

  useEffect(() => {
    setDraftTree(appliedTree)
    setEditingPath((path) => path && filterNodeAtPath(appliedTree, path) ? path : null)
    setAddMenuOpen(false)
    setAddQuery("")
  }, [appliedTree])

  useEffect(() => {
    if (!addMenuOpen) return

    function closeOnEscape(event: KeyboardEvent) {
      if (event.key === "Escape") setAddMenuOpen(false)
    }

    function closeOnOutsidePointer(event: PointerEvent) {
      const target = event.target
      if (target instanceof Node && addMenuRef.current?.contains(target)) return

      setAddMenuOpen(false)
    }

    window.addEventListener("keydown", closeOnEscape)
    window.addEventListener("pointerdown", closeOnOutsidePointer)
    return () => {
      window.removeEventListener("keydown", closeOnEscape)
      window.removeEventListener("pointerdown", closeOnOutsidePointer)
    }
  }, [addMenuOpen])

  useEffect(() => {
    if (!editingPath) return

    function closeOnEscape(event: KeyboardEvent) {
      if (event.key === "Escape") setEditingPath(null)
    }

    function closeOnOutsidePointer(event: PointerEvent) {
      const target = event.target
      if (target instanceof Node && editorRef.current?.contains(target)) return

      setEditingPath(null)
    }

    window.addEventListener("keydown", closeOnEscape)
    window.addEventListener("pointerdown", closeOnOutsidePointer)
    return () => {
      window.removeEventListener("keydown", closeOnEscape)
      window.removeEventListener("pointerdown", closeOnOutsidePointer)
    }
  }, [editingPath])

  if (controls.length === 0) return null

  function updateTree(nextTree: FilterTree, nextEditingPath = editingPath) {
    setDraftTree(normalizedFilterTree(nextTree))
    setEditingPath(nextEditingPath)
  }

  function applyTree(tree = draftTree) {
    const normalized = normalizedFilterTree(tree)
    const nextQ = topFilterChildren(normalized).length > 0 ? encodeFilterTree(normalized) : null
    navigate(dashboardLinkFromSearch(pathname, search, {
      q: nextQ,
      page: null,
      smart_folder_id: null,
      state: null,
      repository_id: null,
      kind: null,
      trigger_kind: null,
      job_id: null,
      attention: null,
      tag_ids: null,
      pr: null,
      age: null
    }))
  }

  function openAddMenu(target: PendingAddTarget) {
    setPendingAddTarget(target)
    setEditingPath(null)
    setAddMenuOpen(true)
    setAddQuery("")
  }

  function addFilter(meta: DashboardFilterSchemaField) {
    const chip = defaultFilterChip(meta)
    const children = topFilterChildren(draftTree).slice()
    let nextPath: FilterPath

    if (pendingAddTarget.kind === "or") {
      const index = pendingAddTarget.index
      const slot = children[index]
      const negated = filterSlotIsNegated(slot)
      const inner = filterSlotInner(slot)
      const currentOr = inner && "or" in inner && Array.isArray(inner.or) ? inner.or : [ inner ].filter(Boolean) as FilterNode[]
      const nextOr = [ ...currentOr, chip ]
      children[index] = negated ? { not: { or: nextOr } } : { or: nextOr }
      nextPath = [ index, nextOr.length - 1 ]
    } else {
      children.push(chip)
      nextPath = [ children.length - 1 ]
    }

    const nextTree = { and: children }
    updateTree(nextTree, nextPath)
    setAddMenuOpen(false)
    applyTree(nextTree)
  }

  function editChip(path: FilterPath, nextChip: FilterChip) {
    const nextTree = replaceFilterNodeAtPath(draftTree, path, nextChip)
    updateTree(nextTree, path)
    applyTree(nextTree)
  }

  function removeChip(path: FilterPath) {
    const nextTree = removeFilterNodeAtPath(draftTree, path)
    updateTree(nextTree, null)
    applyTree(nextTree)
  }

  function toggleNegation(index: number) {
    const nextTree = toggleFilterNegation(draftTree, index)
    updateTree(nextTree, null)
    applyTree(nextTree)
  }

  return (
    <div className="space-y-2 rounded border border-gray-200 bg-white px-3 py-2">
      <div className="relative flex flex-wrap items-center gap-2">
        {draftChildren.map((node, index) => (
          <FilterNodeChip
            controls={controls}
            index={index}
            key={index}
            node={node}
            onAddOr={(targetIndex) => openAddMenu({ kind: "or", index: targetIndex })}
            onEdit={setEditingPath}
            onRemove={removeChip}
            onToggleNegation={toggleNegation}
          />
        ))}
        {draftChildren.length > 0 ? null : <span className="text-sm text-gray-400">No filters</span>}
        <button
          className="inline-flex items-center gap-1 rounded border border-dashed border-gray-300 px-2 py-1.5 text-sm text-gray-600 hover:border-gray-400 hover:text-gray-900"
          onClick={() => openAddMenu({ kind: "and" })}
          type="button"
        >
          + Add filter
        </button>
        {hasFilters ? (
          <Link className="text-sm text-gray-500 underline hover:text-gray-700" to={clearFiltersLink(pathname, search)}>
            Clear filters
          </Link>
        ) : null}
        {addMenuOpen ? (
          <div className="absolute left-0 top-full z-20 mt-1 w-72 rounded border border-gray-200 bg-white shadow-lg" ref={addMenuRef}>
            <input
              autoFocus
              className="block w-full rounded-t border-b border-gray-200 px-3 py-2 text-sm focus:outline-none"
              onChange={(event) => setAddQuery(event.target.value)}
              placeholder="Search filters..."
              type="search"
              value={addQuery}
            />
            <div className="max-h-72 overflow-y-auto py-1">
              {filteredControls.map((control) => (
                <button
                  aria-label={`${control.label} ${control.bucket}`}
                  className="flex w-full items-center justify-between gap-2 px-3 py-2 text-left text-sm hover:bg-gray-50"
                  key={control.field}
                  onClick={() => addFilter(control)}
                  type="button"
                >
                  <span>{control.label}</span>
                  <span className="text-xs text-gray-400">{control.bucket}</span>
                </button>
              ))}
              {filteredControls.length === 0 ? <div className="px-3 py-2 text-sm text-gray-400">No matching filters</div> : null}
            </div>
          </div>
        ) : null}

        {editingChip && editingMeta && "field" in editingChip ? (
          <FilterChipEditor
            chip={editingChip}
            editorRef={editorRef}
            meta={editingMeta}
            onChange={(nextChip) => editChip(editingPath!, nextChip)}
          />
        ) : null}
      </div>

    </div>
  )
}

type FilterChip = {
  field: string
  op: string
  value?: unknown
}

type FilterGroup = {
  and?: FilterNode[]
  or?: FilterNode[]
  not?: FilterNode
}

type FilterNode = FilterChip | FilterGroup
type FilterTree = FilterGroup
type FilterPath = number[]
type PendingAddTarget = { kind: "and" } | { kind: "or"; index: number }

const legacyFilterKeys = [ "state", "repository_id", "kind", "trigger_kind", "job_id", "attention", "tag_ids", "pr", "age" ]

function FilterNodeChip({
  node,
  index,
  controls,
  onEdit,
  onRemove,
  onAddOr,
  onToggleNegation
}: {
  node: FilterNode
  index: number
  controls: DashboardFilterSchemaField[]
  onEdit: (path: FilterPath) => void
  onRemove: (path: FilterPath) => void
  onAddOr: (index: number) => void
  onToggleNegation: (index: number) => void
}) {
  const negated = filterSlotIsNegated(node)
  const inner = filterSlotInner(node)
  if (isFilterChip(inner)) {
    return (
      <span className={filterChipClass(negated)}>
        <button className={filterNotClass(negated)} onClick={() => onToggleNegation(index)} title={negated ? "Remove NOT" : "Wrap in NOT"} type="button">NOT</button>
        <FilterChipButton chip={inner} controls={controls} negated={negated} onClick={() => onEdit([ index ])} />
        <button aria-label={`Remove ${filterChipLabel(inner, controls)} filter`} className="text-gray-400 hover:text-gray-700" onClick={() => onRemove([ index ])} type="button">x</button>
        <button aria-label={`Add OR filter to ${filterChipLabel(inner, controls)}`} className="rounded border border-dashed border-indigo-300 px-1.5 py-0.5 text-xs font-medium text-indigo-700 hover:bg-indigo-50" onClick={() => onAddOr(index)} type="button">+ or</button>
      </span>
    )
  }

  if (inner && "or" in inner && Array.isArray(inner.or)) {
    return (
      <span className={negated ? "inline-flex flex-wrap items-center gap-1 rounded border border-rose-300 bg-rose-50 px-1.5 py-0.5 text-sm" : "inline-flex flex-wrap items-center gap-1 rounded border border-indigo-300 bg-indigo-50 px-1.5 py-0.5 text-sm"}>
        <button className={filterNotClass(negated)} onClick={() => onToggleNegation(index)} title={negated ? "Remove NOT" : "Wrap in NOT"} type="button">NOT</button>
        <span className={negated ? "text-xs font-semibold text-rose-700" : "text-xs font-semibold text-indigo-700"}>(</span>
        {inner.or.map((child, childIndex) => (
          <span className="inline-flex items-center gap-1" key={childIndex}>
            {childIndex > 0 ? <span className="text-xs font-semibold uppercase text-indigo-500">or</span> : null}
            {isFilterChip(child) ? (
              <span className="inline-flex items-center gap-1 rounded border border-gray-300 bg-gray-50 px-2 py-1">
                <FilterChipButton chip={child} controls={controls} onClick={() => onEdit([ index, childIndex ])} />
                <button aria-label={`Remove ${filterChipLabel(child, controls)} filter`} className="text-gray-400 hover:text-gray-700" onClick={() => onRemove([ index, childIndex ])} type="button">x</button>
              </span>
            ) : (
              <span className="rounded border border-amber-300 bg-amber-50 px-2 py-1 text-amber-800">complex filter</span>
            )}
          </span>
        ))}
        <button className="rounded border border-dashed border-indigo-400 px-1.5 py-0.5 text-xs font-medium text-indigo-700 hover:bg-indigo-100" onClick={() => onAddOr(index)} type="button">+ or</button>
        <span className={negated ? "text-xs font-semibold text-rose-700" : "text-xs font-semibold text-indigo-700"}>)</span>
      </span>
    )
  }

  return <span className="rounded border border-amber-300 bg-amber-50 px-2 py-1 text-sm text-amber-800">complex filter</span>
}

function FilterChipButton({ chip, controls, negated = false, onClick }: { chip: FilterChip; controls: DashboardFilterSchemaField[]; negated?: boolean; onClick: () => void }) {
  const meta = filterMetaFor(controls, chip.field)
  const label = `${negated ? "NOT " : ""}${meta?.label || chip.field} ${humanizeOp(chip.op)}${isPredicateOp(chip.op) ? "" : ` ${formatFilterValue(chip, meta)}`}`
  return (
    <button aria-label={label} className="inline-flex items-baseline gap-1 text-left" onClick={onClick} type="button">
      <span className="font-medium text-gray-700">{negated ? "NOT " : ""}{meta?.label || chip.field}</span>
      <span className="text-xs text-gray-500">{humanizeOp(chip.op)}</span>
      {isPredicateOp(chip.op) ? null : <span className="font-mono text-gray-900">{formatFilterValue(chip, meta)}</span>}
    </button>
  )
}

function FilterChipEditor({ chip, editorRef, meta, onChange }: { chip: FilterChip; editorRef: RefObject<HTMLDivElement>; meta: DashboardFilterSchemaField; onChange: (chip: FilterChip) => void }) {
  function updateOp(op: string) {
    onChange({ field: chip.field, op, value: defaultFilterValue(meta, op) })
  }

  return (
    <div aria-label={`${meta.label} filter settings`} className="absolute left-0 top-full z-30 mt-2 w-[min(28rem,calc(100vw-3rem))] space-y-3 rounded border border-gray-200 bg-white p-3 shadow-lg" ref={editorRef} role="dialog">
      <div className="text-xs font-semibold uppercase text-gray-500">{meta.label}</div>
      <div className="flex flex-wrap items-end gap-3">
        <label className="block text-xs font-medium uppercase text-gray-500" htmlFor={`filter-op-${meta.field}`}>
          Operator
          <select className="mt-1 block rounded border border-gray-300 bg-white px-2 py-1.5 text-sm normal-case text-gray-700" id={`filter-op-${meta.field}`} onChange={(event) => updateOp(event.target.value)} value={chip.op}>
            {meta.operators.map((op) => <option key={op} value={op}>{humanizeOp(op)}</option>)}
          </select>
        </label>
        <FilterValueEditor chip={chip} meta={meta} onChange={onChange} />
      </div>
    </div>
  )
}

function FilterValueEditor({ chip, meta, onChange }: { chip: FilterChip; meta: DashboardFilterSchemaField; onChange: (chip: FilterChip) => void }) {
  if (isPredicateOp(chip.op)) return null

  const options = filterOptions(meta)
  const multi = isMultiValueOp(chip.op)
  if (options.length > 0 && !meta.typeahead) {
    const selected = multi ? Array.isArray(chip.value) ? chip.value.map(String) : [] : [ String(chip.value ?? "") ]
    return (
      <label className="block text-xs font-medium uppercase text-gray-500" htmlFor={`filter-value-${meta.field}`}>
        Value
        <select
          className="mt-1 block min-w-44 rounded border border-gray-300 bg-white px-2 py-1.5 text-sm normal-case text-gray-700"
          id={`filter-value-${meta.field}`}
          multiple={multi}
          onChange={(event) => {
            const value = multi ? Array.from(event.target.selectedOptions).map((option) => option.value) : event.target.value
            onChange({ ...chip, value })
          }}
          size={multi ? Math.min(Math.max(options.length, 2), 5) : undefined}
          value={multi ? selected : selected[0]}
        >
          {options.map((option) => <option key={String(option.value)} value={String(option.value)}>{option.label}</option>)}
        </select>
      </label>
    )
  }

  if (meta.bucket === "date") return <DateFilterValueEditor chip={chip} onChange={onChange} />
  if (meta.bucket === "number") return <NumberFilterValueEditor chip={chip} onChange={onChange} />

  return (
    <label className="block text-xs font-medium uppercase text-gray-500" htmlFor={`filter-value-${meta.field}`}>
      Value
      <input
        className="mt-1 block w-56 rounded border border-gray-300 bg-white px-2 py-1.5 text-sm normal-case text-gray-700"
        id={`filter-value-${meta.field}`}
        onChange={(event) => onChange({ ...chip, value: event.target.value })}
        type="text"
        value={String(chip.value ?? "")}
      />
    </label>
  )
}

function DateFilterValueEditor({ chip, onChange }: { chip: FilterChip; onChange: (chip: FilterChip) => void }) {
  if (chip.op === "within_last" || chip.op === "more_than_ago") {
    const value = isObjectValue(chip.value) ? chip.value : { n: 7, unit: "days" }
    return (
      <div className="flex items-end gap-2">
        <label className="block text-xs font-medium uppercase text-gray-500" htmlFor="filter-date-amount">
          Amount
          <input className="mt-1 block w-20 rounded border border-gray-300 bg-white px-2 py-1.5 text-sm normal-case text-gray-700" id="filter-date-amount" min="0" onChange={(event) => onChange({ ...chip, value: { ...value, n: Number(event.target.value || 0) } })} type="number" value={Number(value.n || 0)} />
        </label>
        <label className="block text-xs font-medium uppercase text-gray-500" htmlFor="filter-date-unit">
          Unit
          <select className="mt-1 block rounded border border-gray-300 bg-white px-2 py-1.5 text-sm normal-case text-gray-700" id="filter-date-unit" onChange={(event) => onChange({ ...chip, value: { ...value, unit: event.target.value } })} value={String(value.unit || "days")}>
            {["minutes", "hours", "days", "weeks", "months"].map((unit) => <option key={unit} value={unit}>{unit}</option>)}
          </select>
        </label>
      </div>
    )
  }

  if (chip.op === "between") {
    const value = Array.isArray(chip.value) ? chip.value : [ "", "" ]
    return (
      <div className="flex items-end gap-2">
        <label className="block text-xs font-medium uppercase text-gray-500" htmlFor="filter-date-from">
          From
          <input className="mt-1 block rounded border border-gray-300 bg-white px-2 py-1.5 text-sm normal-case text-gray-700" id="filter-date-from" onChange={(event) => onChange({ ...chip, value: [ event.target.value, value[1] || "" ] })} type="date" value={String(value[0] || "").slice(0, 10)} />
        </label>
        <label className="block text-xs font-medium uppercase text-gray-500" htmlFor="filter-date-to">
          To
          <input className="mt-1 block rounded border border-gray-300 bg-white px-2 py-1.5 text-sm normal-case text-gray-700" id="filter-date-to" onChange={(event) => onChange({ ...chip, value: [ value[0] || "", event.target.value ] })} type="date" value={String(value[1] || "").slice(0, 10)} />
        </label>
      </div>
    )
  }

  return (
    <label className="block text-xs font-medium uppercase text-gray-500" htmlFor="filter-date-value">
      Value
      <input className="mt-1 block rounded border border-gray-300 bg-white px-2 py-1.5 text-sm normal-case text-gray-700" id="filter-date-value" onChange={(event) => onChange({ ...chip, value: event.target.value })} type="date" value={String(chip.value || "").slice(0, 10)} />
    </label>
  )
}

function NumberFilterValueEditor({ chip, onChange }: { chip: FilterChip; onChange: (chip: FilterChip) => void }) {
  if (chip.op === "between") {
    const value = Array.isArray(chip.value) ? chip.value : [ null, null ]
    return (
      <div className="flex items-end gap-2">
        <label className="block text-xs font-medium uppercase text-gray-500" htmlFor="filter-number-min">
          Min
          <input className="mt-1 block w-28 rounded border border-gray-300 bg-white px-2 py-1.5 text-sm normal-case text-gray-700" id="filter-number-min" onChange={(event) => onChange({ ...chip, value: [ event.target.value === "" ? null : Number(event.target.value), value[1] ?? null ] })} type="number" value={typeof value[0] === "number" ? value[0] : ""} />
        </label>
        <label className="block text-xs font-medium uppercase text-gray-500" htmlFor="filter-number-max">
          Max
          <input className="mt-1 block w-28 rounded border border-gray-300 bg-white px-2 py-1.5 text-sm normal-case text-gray-700" id="filter-number-max" onChange={(event) => onChange({ ...chip, value: [ value[0] ?? null, event.target.value === "" ? null : Number(event.target.value) ] })} type="number" value={typeof value[1] === "number" ? value[1] : ""} />
        </label>
      </div>
    )
  }

  return (
    <label className="block text-xs font-medium uppercase text-gray-500" htmlFor="filter-number-value">
      Value
      <input className="mt-1 block w-32 rounded border border-gray-300 bg-white px-2 py-1.5 text-sm normal-case text-gray-700" id="filter-number-value" onChange={(event) => onChange({ ...chip, value: event.target.value === "" ? null : Number(event.target.value) })} type="number" value={typeof chip.value === "number" ? chip.value : ""} />
    </label>
  )
}

function DashboardTable({ payload, prefix }: { payload: DashboardPayload; prefix: string }) {
  const queryClient = useQueryClient()
  const updateSort = useMutation({
    mutationFn: updateDashboardPreferences,
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["dashboard"] })
    }
  })
  const sortState: DashboardSortState = {
    column: sortValue(payload.preferences.sort, "column") || payload.controls.sort_columns[0] || "title",
    direction: sortValue(payload.preferences.sort, "direction") || "desc",
    pending: updateSort.isPending,
    sortableColumns: payload.controls.sort_columns,
    onSort: (column) => {
      const sortColumn = sortableColumnFor(payload.subject, column)
      if (!sortColumn || !payload.controls.sort_columns.includes(sortColumn)) return

      const currentColumn = sortValue(payload.preferences.sort, "column") || payload.controls.sort_columns[0] || "title"
      const currentDirection = sortValue(payload.preferences.sort, "direction") || "desc"
      const nextDirection = currentColumn === sortColumn && currentDirection === "asc" ? "desc" : "asc"
      updateSort.mutate({
        subject: payload.subject,
        sort_column: sortColumn,
        sort_direction: nextDirection
      })
    }
  }

  if (payload.view === "kanban") return <DashboardKanban payload={payload} prefix={prefix} />

  if (payload.items.length === 0) {
    return <div className="rounded border border-gray-200 bg-white p-6 text-sm text-gray-500">No {subjectLabel(payload.subject, 2)} match this view.</div>
  }

  const columns = dashboardVisibleColumns(payload)
  if (payload.subject === "job") return <JobsDashboardTable columns={columns} items={payload.items.filter((item): item is DashboardJobItem => item.type === "job")} prefix={prefix} sortState={sortState} />
  if (payload.subject === "workflow") return <WorkflowsTable columns={columns} items={payload.items.filter((item): item is DashboardWorkflowItem => item.type === "workflow")} prefix={prefix} sortState={sortState} />

  return <EpicsTable columns={columns} items={payload.items.filter((item): item is DashboardEpicItem => item.type === "epic")} prefix={prefix} sortState={sortState} />
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

type DashboardSortState = {
  column: string
  direction: string
  pending: boolean
  sortableColumns: string[]
  onSort: (column: string) => void
}

function JobsDashboardTable({ items, columns, prefix, sortState }: { items: DashboardJobItem[]; columns: string[]; prefix: string; sortState: DashboardSortState }) {
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
        sortState={sortState}
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

  if (selectedIds.length === 0) {
    if (notice) {
      return (
        <div className="rounded border border-emerald-200 bg-emerald-50 px-3 py-2 text-sm text-emerald-700" role="status">
          {notice}
        </div>
      )
    }

    return null
  }

  return (
    <div className="flex flex-wrap items-center justify-between gap-3 rounded border border-gray-200 bg-gray-50 px-3 py-2 text-sm">
      <div>
        <span className="font-medium text-gray-900">{selectedIds.length} selected</span>
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
  prefix,
  sortState
}: {
  items: DashboardJobItem[]
  columns: string[]
  selectedIds: Set<number>
  allSelected: boolean
  onToggleAll: () => void
  onToggleOne: (id: number) => void
  prefix: string
  sortState: DashboardSortState
}) {
  return (
    <div className="overflow-x-auto rounded border border-gray-200 bg-white">
      <table className="min-w-full divide-y divide-gray-200 text-sm">
        <thead className="bg-gray-50 text-left text-xs font-semibold uppercase text-gray-500">
          <tr>
            {columns.map((column) => (
              <th aria-sort={columnAriaSort("job", column, sortState)} className={column === "checkbox" ? "w-10 px-4 py-2" : "px-4 py-2"} key={column}>
                {column === "checkbox" ? <input aria-label="Select all jobs" checked={allSelected} onChange={onToggleAll} type="checkbox" /> : <SortableColumnHeader column={column} sortState={sortState} subject="job" />}
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

function EpicsTable({ items, columns, prefix, sortState }: { items: DashboardEpicItem[]; columns: string[]; prefix: string; sortState: DashboardSortState }) {
  return (
    <div className="overflow-x-auto rounded border border-gray-200 bg-white">
      <table className="min-w-full divide-y divide-gray-200 text-sm">
        <thead className="bg-gray-50 text-left text-xs font-semibold uppercase text-gray-500">
          <tr>
            {columns.map((column) => <th aria-sort={columnAriaSort("epic", column, sortState)} className="px-4 py-2" key={column}><SortableColumnHeader column={column} sortState={sortState} subject="epic" /></th>)}
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

function WorkflowsTable({ items, columns, prefix, sortState }: { items: DashboardWorkflowItem[]; columns: string[]; prefix: string; sortState: DashboardSortState }) {
  return (
    <div className="overflow-x-auto rounded border border-gray-200 bg-white">
      <table className="min-w-full divide-y divide-gray-200 text-sm">
        <thead className="bg-gray-50 text-left text-xs font-semibold uppercase text-gray-500">
          <tr>
            {columns.map((column) => <th aria-sort={columnAriaSort("workflow", column, sortState)} className="px-4 py-2" key={column}><SortableColumnHeader column={column} sortState={sortState} subject="workflow" /></th>)}
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

function SortableColumnHeader({ subject, column, sortState }: { subject: DashboardSubject; column: string; sortState: DashboardSortState }) {
  const label = dashboardColumnLabel(subject, column)
  const sortColumn = sortableColumnFor(subject, column)
  if (!sortColumn || !sortState.sortableColumns.includes(sortColumn)) return <span>{label}</span>

  const active = sortState.column === sortColumn
  const nextDirection = active && sortState.direction === "asc" ? "desc" : "asc"

  return (
    <button
      aria-label={`Sort by ${label} ${sortDirectionLabel(nextDirection).toLowerCase()}`}
      className={`inline-flex items-center gap-1 text-left font-semibold uppercase ${active ? "text-gray-900" : "text-gray-500 hover:text-gray-900"}`}
      disabled={sortState.pending}
      onClick={() => sortState.onSort(column)}
      type="button"
    >
      <span>{label}</span>
      {active ? <span aria-hidden="true" className="text-[11px] leading-none text-gray-700">{sortState.direction === "asc" ? "↑" : "↓"}</span> : null}
    </button>
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

function smartFolderFiltersFromTree(tree: FilterTree) {
  const normalized = normalizedFilterTree(tree)
  const filters: Record<string, string> = {}
  if (topFilterChildren(normalized).length > 0) filters.filter = JSON.stringify(normalized)
  return filters
}

function filterTreeFromPayload(filter: DashboardPayload["filter"]): FilterTree {
  return normalizedFilterTree(filter && typeof filter === "object" ? filter as FilterTree : null)
}

function decodeFilterTree(raw: string | null): FilterTree | null {
  if (!raw) return null

  try {
    const padded = raw.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(raw.length / 4) * 4, "=")
    const json = decodeURIComponent(escape(atob(padded)))
    const parsed = JSON.parse(json)
    return parsed && typeof parsed === "object" ? parsed : null
  } catch (_error) {
    return null
  }
}

function encodeFilterTree(tree: FilterTree) {
  const json = JSON.stringify(normalizedFilterTree(tree))
  return btoa(unescape(encodeURIComponent(json))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}

function normalizedFilterTree(tree: FilterTree | null): FilterTree {
  const children = topFilterChildren(tree).filter(Boolean)
  return { and: children }
}

function topFilterChildren(tree: FilterTree | FilterNode | null): FilterNode[] {
  if (!tree || typeof tree !== "object") return []
  if ("and" in tree && Array.isArray(tree.and)) return tree.and
  if (isFilterChip(tree) || ("or" in tree && Array.isArray(tree.or)) || ("not" in tree && tree.not)) return [ tree as FilterNode ]
  return []
}

function isFilterChip(node: unknown): node is FilterChip {
  return Boolean(node && typeof node === "object" && "field" in node && typeof (node as FilterChip).field === "string")
}

function filterSlotInner(node: FilterNode | undefined): FilterNode | undefined {
  if (node && "not" in node && node.not) return node.not
  return node
}

function filterSlotIsNegated(node: FilterNode | undefined) {
  return Boolean(node && "not" in node && node.not)
}

function filterNodeAtPath(tree: FilterTree, path: FilterPath): FilterNode | null {
  const slot = topFilterChildren(tree)[path[0]]
  const inner = filterSlotInner(slot)
  if (path.length === 1) return inner || null
  if (!inner || !("or" in inner) || !Array.isArray(inner.or)) return null
  return inner.or[path[1]] || null
}

function replaceFilterNodeAtPath(tree: FilterTree, path: FilterPath, node: FilterNode): FilterTree {
  const children = topFilterChildren(tree).slice()
  const slot = children[path[0]]
  const negated = filterSlotIsNegated(slot)
  if (path.length === 1) {
    children[path[0]] = negated ? { not: node } : node
    return { and: children }
  }

  const inner = filterSlotInner(slot)
  if (!inner || !("or" in inner) || !Array.isArray(inner.or)) return tree
  const nextOr = inner.or.slice()
  nextOr[path[1]] = node
  children[path[0]] = negated ? { not: { or: nextOr } } : { or: nextOr }
  return { and: children }
}

function removeFilterNodeAtPath(tree: FilterTree, path: FilterPath): FilterTree {
  const children = topFilterChildren(tree).slice()
  if (path.length === 1) {
    children.splice(path[0], 1)
    return { and: children }
  }

  const slot = children[path[0]]
  const negated = filterSlotIsNegated(slot)
  const inner = filterSlotInner(slot)
  if (!inner || !("or" in inner) || !Array.isArray(inner.or)) return tree
  const nextOr = inner.or.slice()
  nextOr.splice(path[1], 1)
  if (nextOr.length === 0) children.splice(path[0], 1)
  else if (nextOr.length === 1) children[path[0]] = negated ? { not: nextOr[0] } : nextOr[0]
  else children[path[0]] = negated ? { not: { or: nextOr } } : { or: nextOr }
  return { and: children }
}

function toggleFilterNegation(tree: FilterTree, index: number): FilterTree {
  const children = topFilterChildren(tree).slice()
  const slot = children[index]
  if (!slot) return tree
  children[index] = filterSlotIsNegated(slot) && "not" in slot && slot.not ? slot.not : { not: slot }
  return { and: children }
}

function filterMetaFor(schema: DashboardFilterSchemaField[], field: string) {
  return schema.find((candidate) => candidate.field === field) || null
}

function defaultFilterChip(meta: DashboardFilterSchemaField): FilterChip {
  const op = meta.operators[0] || "is"
  return { field: meta.field, op, value: defaultFilterValue(meta, op) }
}

function defaultFilterValue(meta: DashboardFilterSchemaField, op: string): unknown {
  if (isPredicateOp(op)) return null
  if (isMultiValueOp(op)) return []
  if (meta.bucket === "date") {
    if (op === "within_last" || op === "more_than_ago") return { n: 7, unit: "days" }
    if (op === "between") return [ "", "" ]
    return ""
  }
  if (meta.bucket === "number") return op === "between" ? [ null, null ] : null
  return filterOptions(meta)[0]?.value ?? ""
}

function filterOptions(meta: DashboardFilterSchemaField): DashboardFilterOption[] {
  return normalizedOptions(meta)
}

function filterChipLabel(chip: FilterChip, controls: DashboardFilterSchemaField[]) {
  return filterMetaFor(controls, chip.field)?.label || chip.field
}

function formatFilterValue(chip: FilterChip, meta: DashboardFilterSchemaField | null) {
  if (chip.value === null || chip.value === undefined || chip.value === "") return "(unset)"
  if (Array.isArray(chip.value)) return chip.value.map((value) => labelForOption(value, meta)).join(", ")
  if (isObjectValue(chip.value)) {
    if ("n" in chip.value && "unit" in chip.value) return `${chip.value.n} ${chip.value.unit}${chip.op === "more_than_ago" ? " ago" : ""}`
    return JSON.stringify(chip.value)
  }
  return labelForOption(chip.value, meta)
}

function labelForOption(value: unknown, meta: DashboardFilterSchemaField | null) {
  if (!meta) return String(value)
  return filterOptions(meta).find((option) => String(option.value) === String(value))?.label || String(value)
}

function isPredicateOp(op: string) {
  return ["is_set", "is_unset", "is_true", "is_false"].includes(op)
}

function isMultiValueOp(op: string) {
  return ["is_one_of", "is_none_of", "contains_any", "contains_all", "contains_none"].includes(op)
}

function isObjectValue(value: unknown): value is Record<string, unknown> {
  return Boolean(value && typeof value === "object" && !Array.isArray(value))
}

function humanizeOp(op: string) {
  return op.replace(/_/g, " ")
}

function filterChipClass(negated: boolean) {
  return negated
    ? "inline-flex flex-wrap items-center gap-1 rounded border border-rose-300 bg-rose-50 px-2 py-1 text-sm"
    : "inline-flex flex-wrap items-center gap-1 rounded border border-gray-300 bg-gray-50 px-2 py-1 text-sm"
}

function filterNotClass(negated: boolean) {
  return negated
    ? "rounded bg-rose-200 px-1 py-0.5 text-[10px] font-bold text-rose-900"
    : "rounded border border-gray-300 px-1 py-0.5 text-[10px] font-bold text-gray-400 hover:border-rose-300 hover:bg-rose-50 hover:text-rose-700"
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
  return `flex min-w-0 items-center justify-between gap-2 rounded px-2 py-1.5 text-sm ${active ? "bg-blue-50 font-medium text-blue-700" : "text-gray-700 hover:bg-gray-100"}`
}

function bulkButtonClass(disabled: boolean, tone: "default" | "danger" = "default") {
  if (disabled) return "rounded border border-gray-200 px-3 py-1 text-gray-300"
  if (tone === "danger") return "rounded border border-red-300 px-3 py-1 text-red-700 hover:bg-red-50"

  return "rounded border border-gray-300 px-3 py-1 text-gray-700 hover:bg-white"
}

function uniqueValue(value: string, index: number, values: string[]) {
  return values.indexOf(value) === index
}

function normalizedOptions(field: DashboardFilterSchemaField): DashboardFilterOption[] {
  return (field.values || []).map((option) => {
    if (typeof option === "string") return { value: option, label: humanizeOption(option) }
    return option
  })
}

function subjectLabel(subject: DashboardSubject, count: number) {
  const label = subject === "job" ? "job" : subject
  return count === 1 ? label : `${label}s`
}

function sortValue(sort: Record<string, string>, key: string) {
  return sort[key]
}

function sortDirectionLabel(direction: string) {
  return direction === "asc" ? "Ascending" : "Descending"
}

function sortableColumnFor(subject: DashboardSubject, column: string) {
  const aliases: Record<DashboardSubject, Record<string, string>> = {
    epic: {
      epic: "title",
      title: "title",
      updated: "updated_at"
    },
    job: {
      issue: "title",
      title: "title",
      started: "started_at"
    },
    workflow: {
      workflow: "title",
      title: "title",
      started: "started_at",
      finished: "finished_at"
    }
  }

  return aliases[subject][column] || column
}

function columnAriaSort(subject: DashboardSubject, column: string, sortState: DashboardSortState) {
  const sortColumn = sortableColumnFor(subject, column)
  if (!sortColumn || sortState.column !== sortColumn) return undefined

  return sortState.direction === "asc" ? "ascending" : "descending"
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

function errorMessage(error: Error, fallback: string) {
  return error instanceof ApiError ? error.message : fallback
}

function formatDate(value: string | null) {
  if (!value) return "-"

  return new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(new Date(value))
}
