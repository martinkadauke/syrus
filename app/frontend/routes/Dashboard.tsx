import { SortableColumnHeader, TimestampCell, useMediaQuery, EpicProgressBar, EpicStuckBadge, NeutralStatePill, OwnerBadge, RepositorySlugLink, workflowLabel } from "./dashboard/components"
import { DashboardKanban } from "./dashboard/KanbanBoard"
import { JobsDashboardTable } from "./dashboard/JobsTable"
import { dashboardEmptyState, bulkButtonClass, columnAriaSort, compactText, dashboardLinkFromSearch, dashboardVisibleColumns, epicDateValue, epicTableColumns, formatDate, pageLink, sortValue, sortableColumnFor, subjectLabel, uniqueValue, withRoutePrefix, workflowDateValue } from "./dashboard/helpers"
import type { DashboardSortState } from "./dashboard/helpers"
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"
import { useEffect, useMemo, useState } from "react"
import { Link, useLocation, useNavigate } from "react-router-dom"
import { useT } from "../hooks/useT"
import { useBackendOutage } from "../hooks/useBackendUpdate"
import { fetchBootstrap, readInitialBootstrap, type BootstrapPayload } from "../api/bootstrap"
import { ApiError } from "../api/client"
import { SlugHoverCard } from "../components/SlugHoverCard"
import { DashboardSmartFolderNav } from "../components/DashboardSmartFolderNav"
import { OnboardingEmptyState, useSetupStatus } from "../components/OnboardingEmptyState"
import { NoticeToast } from "../components/NoticeToast"
import { CloseIcon } from "../components/CloseIcon"
import { StatusPill, TonePill } from "../components/StatusPill"
import { FilterBar } from "../components/FilterBar"
import { useDismissiblePopup } from "../lib/useDismissiblePopup"
import { bulkDashboardEpics, dashboardApiSearch, fetchDashboardChrome, fetchDashboardRows, mergeDashboardPayload, recordDashboardFilterUsage, requestDashboardMainBranchRepair, updateDashboardPreferences, type DashboardHealthBlockedRepository, type DashboardBulkEpicAction, type DashboardEpicItem, type DashboardJobItem, type DashboardPayload, type DashboardSubject, type DashboardWorkflowItem } from "../api/dashboard"
import { errorMessage } from "../lib/errorMessage"

export function DashboardRoute() {
  const location = useLocation()
  const search = dashboardApiSearch(location.pathname, location.search)
  const dashboardChrome = useQuery({
    queryKey: ["dashboard", "chrome", search],
    queryFn: ({ signal }) => fetchDashboardChrome(search, { signal }),
    placeholderData: (previousData) => previousData
  })
  const dashboardRows = useQuery({
    queryKey: ["dashboard", "rows", search],
    queryFn: ({ signal }) => fetchDashboardRows(search, { signal }),
    placeholderData: (previousData) => previousData
  })
  const payload = useMemo(() => {
    if (!dashboardChrome.data || !dashboardRows.data) return null

    return mergeDashboardPayload(dashboardChrome.data, dashboardRows.data)
  }, [dashboardChrome.data, dashboardRows.data])

  const { t } = useT("dashboard")
  if (!payload && (dashboardChrome.isPending || dashboardRows.isPending)) return <main aria-label={t("title")} className="p-6 text-sm text-gray-600 dark:text-gray-300">{t("loading")}</main>
  if (dashboardChrome.isError) return <DashboardError error={dashboardChrome.error} />
  if (dashboardRows.isError) return <DashboardError error={dashboardRows.error} />
  if (!payload) return <main aria-label={t("title")} className="p-6 text-sm text-gray-600 dark:text-gray-300">{t("loading")}</main>

  return <DashboardView pathname={location.pathname} search={location.search} payload={payload} />
}

function DashboardView({ payload, pathname, search }: { payload: DashboardPayload; pathname: string; search: string }) {
  const prefix = pathname.startsWith("/app-shell") ? "/app-shell" : ""
  const isDesktop = useMediaQuery("(min-width: 1024px)", true)
  const initialBootstrap = readInitialBootstrap()
  const bootstrap = useQuery({
    queryKey: ["bootstrap"],
    queryFn: fetchBootstrap,
    enabled: initialBootstrap != null,
    initialData: initialBootstrap ?? undefined,
    staleTime: initialBootstrap ? Number.POSITIVE_INFINITY : 0
  })
  const readiness = bootstrap.data?.setup_status?.readiness
  const { t } = useT("dashboard")

  return (
    <main aria-label={t("title")} className="mx-auto max-w-[96rem] space-y-5 p-6">
      <header className="flex flex-wrap items-center gap-3">
        <h1 className="flex-1 text-3xl font-semibold text-gray-900 dark:text-white">{t("title")}</h1>
        {isDesktop ? <DashboardToolbar pathname={pathname} search={search} payload={payload} showConfiguration={true} /> : null}
        <DashboardCreateActions payload={payload} prefix={prefix} />
      </header>
      <ReadinessPanel prefix={prefix} readiness={readiness} />
      <RepositoryHealthBanners prefix={prefix} repositories={payload.health_blocked_repositories ?? payload.broken_repositories ?? []} />

      {isDesktop ? (
        <>
          <DesktopDashboardControls pathname={pathname} payload={payload} search={search} />
          <DashboardContent pathname={pathname} payload={payload} prefix={prefix} search={search} />
        </>
      ) : (
        <>
          <MobileDashboardControls pathname={pathname} payload={payload} prefix={prefix} search={search} />
          <DashboardContent pathname={pathname} payload={payload} prefix={prefix} search={search} />
        </>
      )}
    </main>
  )
}

export function ReadinessPanel({ prefix, readiness }: { prefix: string; readiness?: NonNullable<NonNullable<BootstrapPayload["setup_status"]>["readiness"]> }) {
  const { t } = useT("dashboard")
  // While the desktop shell's backend update has the containers down,
  // readiness checks fail because the backend is deliberately unreachable —
  // showing them would read as "credentials gone". The sidebar's notice
  // explains what's happening; the warnings return the moment the update
  // ends. During the image-pull half of an update the old backend still
  // serves, so outage stays false and the panel behaves normally.
  const backendOutage = useBackendOutage()
  if (backendOutage) return null
  if (!readiness || readiness.status === "ok") return null

  const failingChecks = readiness.checks.filter((check) => check.status !== "ok")
  if (failingChecks.length === 0) return null

  return (
    <section aria-label={t("system_readiness")} className="rounded border border-amber-200 bg-amber-50 p-4 dark:border-amber-900 dark:bg-amber-950/40">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="text-sm font-semibold text-amber-950 dark:text-amber-100">{t("readiness_title")}</h2>
          <p className="mt-1 text-sm text-amber-900 dark:text-amber-200">{t("readiness_description")}</p>
        </div>
        <Link className="rounded border border-amber-300 bg-white px-3 py-1.5 text-sm font-medium text-amber-900 hover:bg-amber-100 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-100 dark:hover:bg-amber-900" to={`${prefix}/credentials`}>
          {t("open_settings")}
        </Link>
      </div>
      <div className="mt-3 grid gap-2 lg:grid-cols-2">
        {failingChecks.map((check) => (
          <div className="rounded border border-amber-200 bg-white p-3 dark:border-amber-900 dark:bg-gray-950" key={check.key}>
            <div className="flex items-center gap-2">
              <TonePill tone={check.status === "error" ? "red" : "amber"}>{check.status}</TonePill>
              <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100">{check.label}</h3>
              {check.optional ? <span className="text-xs text-gray-500 dark:text-gray-400">{t("optional")}</span> : null}
            </div>
            <p className="mt-2 text-sm text-gray-700 dark:text-gray-200">{check.message}</p>
            {check.remediation ? <p className="mt-1 text-sm text-gray-600 dark:text-gray-300">{check.remediation}</p> : null}
          </div>
        ))}
      </div>
    </section>
  )
}

function RepositoryHealthBanners({ prefix, repositories }: { prefix: string; repositories: DashboardHealthBlockedRepository[] }) {
  const { t } = useT("dashboard")
  const queryClient = useQueryClient()
  const [dismissed, setDismissed] = useState<Set<number>>(() => new Set())
  const requestRepair = useMutation({
    mutationFn: requestDashboardMainBranchRepair,
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["dashboard"] })
    }
  })
  const visible = repositories.filter((repo) => !dismissed.has(repo.id))

  if (visible.length === 0) return null

  return (
    <div className="space-y-2">
      {visible.map((repo) => {
        const repair = repo.main_branch_repair
        const blockingJob = repair?.blocking_job
        const failedJobs = repair?.failed_jobs ?? []
        const isStartingRepair = requestRepair.isPending && requestRepair.variables === repo.repair_path
        const repairError = requestRepair.isError && requestRepair.variables === repo.repair_path
          ? (requestRepair.error instanceof Error ? requestRepair.error.message : t("broken_main_repair_start_failed"))
          : null

        return (
          <div className="flex flex-col gap-2 rounded border border-red-200 bg-red-50 px-4 py-3 text-sm dark:border-red-900 dark:bg-red-950/40 sm:flex-row sm:items-center sm:justify-between" key={repo.id} role="alert">
            <div className="min-w-0">
              <span className="text-red-800 dark:text-red-200">
                <span className="font-mono font-medium">{repo.slug}</span>
                {" — "}{t(repo.main_health === "inconclusive"
                  ? (repo.landing_paused ? "main_health_inconclusive_banner" : "main_health_inconclusive_banner_not_held")
                  : (repo.landing_paused ? "broken_main_banner" : "broken_main_banner_not_held")
                )}
              </span>
              {repair ? (
                <div className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-red-700 dark:text-red-200">
                  {blockingJob ? (
                    <span>
                      {t(repair.blocked_reason === "active" ? "broken_main_repair_active" : "broken_main_repair_waiting")}{" "}
                      <Link className="font-medium underline underline-offset-2" to={withRoutePrefix(blockingJob.job_path, prefix)}>
                        {blockingJob.slug}
                      </Link>
                    </span>
                  ) : null}
                  {failedJobs.length > 0 ? (
                    <span>
                      {t("broken_main_repair_failed_jobs")}{" "}
                      {failedJobs.map((job, index) => (
                        <span key={job.id}>
                          {index > 0 ? ", " : null}
                          <Link className="font-medium underline underline-offset-2" to={withRoutePrefix(job.job_path, prefix)}>
                            {job.slug}
                          </Link>
                        </span>
                      ))}
                    </span>
                  ) : null}
                  {repair.blocked_reason === "waiting_for_health_signals" ? <span>{t("broken_main_repair_waiting_for_signals")}</span> : null}
                  {repair.blocked_reason === "failed_open_cap" ? <span>{t("broken_main_repair_cap")}</span> : null}
                  {repairError ? <span className="font-medium">{repairError}</span> : null}
                </div>
              ) : null}
            </div>
            <div className="flex shrink-0 items-center gap-2">
              {repair?.can_request ? (
                <button
                  className="rounded border border-red-300 bg-white px-2 py-1 text-xs font-medium text-red-800 hover:bg-red-50 disabled:cursor-not-allowed disabled:opacity-60 dark:border-red-800 dark:bg-red-950 dark:text-red-200 dark:hover:bg-red-900"
                  disabled={isStartingRepair}
                  onClick={() => requestRepair.mutate(repo.repair_path)}
                  type="button"
                >
                  {isStartingRepair ? t("broken_main_repair_starting") : t("broken_main_repair_start")}
                </button>
              ) : null}
              <Link
                className="rounded border border-red-300 bg-white px-2 py-1 text-xs font-medium text-red-800 hover:bg-red-50 dark:border-red-800 dark:bg-red-950 dark:text-red-200 dark:hover:bg-red-900"
                to={withRoutePrefix(repo.repository_path, prefix)}
              >
                {t("broken_main_view_details")}
              </Link>
              <button
                aria-label={t("broken_main_dismiss")}
                className="text-red-500 hover:text-red-700 dark:text-red-400 dark:hover:text-red-200"
                onClick={() => setDismissed((prev) => new Set([...prev, repo.id]))}
                type="button"
              >
                <CloseIcon />
              </button>
            </div>
          </div>
        )
      })}
    </div>
  )
}

function DesktopDashboardControls({ payload, pathname, search }: { payload: DashboardPayload; pathname: string; search: string }) {
  return (
    <div className="flex min-w-0 flex-col gap-3 lg:flex-row lg:items-center">
      <div className="min-w-0 flex-1">
        <DashboardFilterBar pathname={pathname} search={search} payload={payload} />
      </div>
      <OwnershipControls pathname={pathname} search={search} payload={payload} />
    </div>
  )
}

function MobileDashboardControls({ payload, pathname, prefix, search }: { payload: DashboardPayload; pathname: string; prefix: string; search: string }) {
  const { t } = useT("dashboard")
  return (
    <div className="space-y-3">
      <div aria-label={t("controls_label")} className="flex items-center justify-between gap-3 pb-1" role="group">
        <div className="min-w-0 flex-1 overflow-x-auto">
          <SubjectTabs className="inline-flex w-max flex-nowrap overflow-hidden rounded border border-gray-300 bg-white text-sm dark:border-gray-700 dark:bg-gray-900" payload={payload} prefix={prefix} />
        </div>
        <DashboardToolbar pathname={pathname} search={search} payload={payload} showConfiguration={false} />
      </div>
      <details className="group rounded border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-900">
        <summary className="flex cursor-pointer list-none items-center justify-between gap-3 px-4 py-3 text-sm font-medium text-gray-700 dark:text-gray-200">
          <span>{t("folders_and_filters")}</span>
          <span className="text-gray-400 group-open:hidden dark:text-gray-500">{t("show")}</span>
          <span className="hidden text-gray-400 group-open:inline dark:text-gray-500">{t("hide")}</span>
        </summary>
        <div className="space-y-4 border-t border-gray-200 p-4 dark:border-gray-700">
          <OwnershipControls pathname={pathname} search={search} payload={payload} />
          <DashboardFilterBar pathname={pathname} search={search} payload={payload} />
          <DashboardSmartFolderNav payload={payload} prefix={prefix} search={search} />
        </div>
      </details>
    </div>
  )
}

function OwnershipControls({ payload, pathname, search }: { payload: DashboardPayload; pathname: string; search: string }) {
  const { t } = useT("dashboard")
  const navigate = useNavigate()
  if (payload.subject === "epic" || payload.subject === "job") return null
  if (payload.ownership.team_user_count <= 1) return null

  function scopeLink(scope: string) {
    return dashboardLinkFromSearch(pathname, search, {
      ownership_scope: scope === "mine" ? null : scope,
      owner_id: scope === "user" ? payload.ownership.owner_id : null,
      page: null
    })
  }

  return (
    <div className="flex flex-wrap items-center gap-2">
      <nav aria-label={t("ownership_scope_label")} className="inline-flex overflow-hidden rounded border border-gray-300 bg-white text-sm dark:border-gray-700 dark:bg-gray-900">
        {payload.controls.ownership_scopes.map((scope) => (
          <Link
            className={`px-3 py-1.5 font-medium ${payload.ownership.scope === scope.value ? "bg-gray-900 text-white dark:bg-gray-100 dark:text-gray-950" : "text-gray-700 hover:bg-gray-50 dark:text-gray-200 dark:hover:bg-gray-800"}`}
            key={scope.value}
            to={scopeLink(scope.value)}
          >
            {scope.label}
          </Link>
        ))}
      </nav>
      {payload.ownership.scope === "user" ? (
        <label className="sr-only" htmlFor="dashboard-owner-filter">{t("owner_filter_label")}</label>
      ) : null}
      {payload.ownership.scope === "user" ? (
        <select
          className="h-9 rounded border border-gray-300 bg-white px-2 text-sm text-gray-700 dark:border-gray-700 dark:bg-gray-900 dark:text-gray-100"
          id="dashboard-owner-filter"
          onChange={(event) => navigate(dashboardLinkFromSearch(pathname, search, { ownership_scope: "user", owner_id: event.target.value, page: null }))}
          value={payload.ownership.owner_id ?? ""}
        >
          {payload.controls.owners.map((owner) => <option key={owner.id} value={owner.id}>{owner.label}</option>)}
        </select>
      ) : null}
    </div>
  )
}

function DashboardContent({ payload, pathname, prefix, search }: { payload: DashboardPayload; pathname: string; prefix: string; search: string }) {
  const setupStatus = useSetupStatus()

  return (
    <section className="min-w-0 space-y-4">
      <DashboardTable payload={payload} prefix={prefix} setupStatus={setupStatus} />
      {payload.view === "list" ? <Pagination pathname={pathname} search={search} payload={payload} /> : null}
    </section>
  )
}

function DashboardCreateActions({ payload, prefix }: { payload: DashboardPayload; prefix: string }) {
  const { t } = useT("dashboard")
  return (
    <div className="flex flex-wrap gap-2">
      <Link className="rounded bg-blue-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-blue-500" to={withRoutePrefix(payload.paths.new_epic_path, prefix)}>{t("new_epic")}</Link>
      <Link className="rounded bg-green-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-green-500" to={withRoutePrefix(payload.paths.new_job_path, prefix)}>{t("new_job")}</Link>
    </div>
  )
}

function SubjectTabs({ payload, prefix, className = "inline-flex w-max overflow-hidden rounded border border-gray-300 bg-white text-sm dark:border-gray-700 dark:bg-gray-900" }: { payload: DashboardPayload; prefix: string; className?: string }) {
  const { t } = useT("dashboard")
  const subjects: Array<{ key: DashboardSubject; label: string; path: string }> = [
    { key: "epic", label: t("tab_epics"), path: "/dashboard/epics" },
    { key: "job", label: t("tab_jobs"), path: "/dashboard/jobs" },
    { key: "workflow", label: t("tab_workflows"), path: "/dashboard/workflows" }
  ]

  return (
    <nav aria-label={t("subjects")} className={className}>
      {subjects.map((subject) => (
        <Link
          className={`px-3 py-1.5 font-medium ${payload.subject === subject.key ? "bg-blue-50 text-blue-700 ring-1 ring-inset ring-blue-600 dark:bg-blue-950 dark:text-blue-200 dark:ring-blue-500" : "text-gray-700 hover:bg-gray-50 dark:text-gray-200 dark:hover:bg-gray-800"}`}
          key={subject.key}
          to={withRoutePrefix(subject.path, prefix)}
        >
          {subject.label}
        </Link>
      ))}
    </nav>
  )
}

function DashboardToolbar({ payload, pathname, search, showConfiguration = true }: { payload: DashboardPayload; pathname: string; search: string; showConfiguration?: boolean }) {
  const { t } = useT("dashboard")
  const queryClient = useQueryClient()
  const [columnsOpen, setColumnsOpen] = useState(false)
  const [lanesOpen, setLanesOpen] = useState(false)
  const columnsMenuRef = useDismissiblePopup<HTMLDivElement>(columnsOpen, () => setColumnsOpen(false))
  const lanesMenuRef = useDismissiblePopup<HTMLDivElement>(lanesOpen, () => setLanesOpen(false))
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

  return (
    <div className="shrink-0">
      <div className="flex flex-wrap items-center justify-end gap-3">
        <nav aria-label={t("view_label")} className="inline-flex overflow-hidden rounded border border-gray-300 bg-white text-sm dark:border-gray-700 dark:bg-gray-900">
          {payload.controls.views.map((view) => (
            <Link
              className={`px-3 py-1.5 capitalize ${payload.view === view ? "bg-gray-900 text-white dark:bg-gray-100 dark:text-gray-950" : "text-gray-700 hover:bg-gray-50 dark:text-gray-200 dark:hover:bg-gray-800"}`}
              key={view}
              onClick={() =>
                updatePreferences.mutate({
                  subject: payload.subject,
                  active_smart_folder_id: payload.active_smart_folder_id,
                  view
                })
              }
              to={dashboardLinkFromSearch(pathname, search, { view, page: null })}
            >
              {view}
            </Link>
          ))}
        </nav>
        {showConfiguration && payload.view === "list" ? (
          <div className="relative" ref={columnsMenuRef}>
            <button
              aria-label={t("columns")}
              aria-controls="dashboard-columns-menu"
              aria-expanded={columnsOpen}
              aria-haspopup="menu"
              className="inline-flex h-9 w-9 items-center justify-center rounded border border-gray-300 bg-white text-gray-700 hover:bg-gray-50 dark:border-gray-700 dark:bg-gray-900 dark:text-gray-200 dark:hover:bg-gray-800"
              onClick={() => setColumnsOpen((open) => !open)}
              type="button"
            >
              <ColumnsIcon />
            </button>
            {columnsOpen ? (
              <div className="absolute right-0 z-20 mt-2 w-64 rounded border border-gray-200 bg-white p-3 shadow-lg dark:border-gray-700 dark:bg-gray-900" id="dashboard-columns-menu" role="menu">
                <fieldset className="space-y-2">
                  <legend className="text-xs font-semibold uppercase text-gray-500 dark:text-gray-400">{t("visible_columns")}</legend>
                  {payload.controls.columns.optional.map((column) => (
                    <label className="flex items-center gap-2 text-sm text-gray-700 dark:text-gray-200" key={column.key}>
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
        {showConfiguration && payload.view === "kanban" ? (
          <div className="relative" ref={lanesMenuRef}>
            <button
              aria-label={t("kanban_lanes")}
              aria-controls="dashboard-kanban-lanes-menu"
              aria-expanded={lanesOpen}
              aria-haspopup="menu"
              className="inline-flex h-9 w-9 items-center justify-center rounded border border-gray-300 bg-white text-gray-700 hover:bg-gray-50 dark:border-gray-700 dark:bg-gray-900 dark:text-gray-200 dark:hover:bg-gray-800"
              onClick={() => setLanesOpen((open) => !open)}
              type="button"
            >
              <ColumnsIcon />
            </button>
            {lanesOpen ? (
              <div className="absolute right-0 z-20 mt-2 w-64 rounded border border-gray-200 bg-white p-3 shadow-lg dark:border-gray-700 dark:bg-gray-900" id="dashboard-kanban-lanes-menu" role="menu">
                <fieldset className="space-y-2">
                  <legend className="text-xs font-semibold uppercase text-gray-500 dark:text-gray-400">{t("kanban_lanes")}</legend>
                  {payload.controls.kanban_lanes.map((lane) => (
                    <label className="flex items-center gap-2 text-sm text-gray-700 dark:text-gray-200" key={lane.key}>
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
      {updatePreferences.isError ? <p className="mt-1 text-right text-sm text-red-700 dark:text-red-300" role="alert">{errorMessage(updatePreferences.error, t("preferences_error"))}</p> : null}
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
  const activeFolder = payload.smart_folders.find((folder) => folder.id === payload.active_smart_folder_id)
  const keepSmartFolderOnFilter = activeFolder?.kind === "user_defined"

  return (
    <FilterBar
      buildLink={(path, currentSearch, updates) => {
        const nextUpdates = { ...updates }
        if (nextUpdates.smart_folder_id != null && !keepSmartFolderOnFilter) nextUpdates.smart_folder_id = null

        return dashboardLinkFromSearch(path, currentSearch, nextUpdates)
      }}
      filter={payload.filter}
      filterSchema={payload.controls.filter_schema}
      legacyFilterKeys={legacyFilterKeys}
      onFilterApplied={(tree) => {
        void recordDashboardFilterUsage({ subject: payload.subject, filter: tree as Record<string, unknown> }).catch(() => {})
      }}
      pathname={pathname}
      search={search}
      suggestionSearch={{ surface: "dashboard", subject: payload.subject }}
      suggestions={payload.controls.filter_suggestions}
    />
  )
}

const legacyFilterKeys = ["state", "repository_id", "kind", "trigger_kind", "job_id", "attention", "tag_ids", "pr", "age"]

function DashboardTable({ payload, prefix, setupStatus }: { payload: DashboardPayload; prefix: string; setupStatus: ReturnType<typeof useSetupStatus> }) {
  const { t } = useT("dashboard")
  const queryClient = useQueryClient()
  const updateSort = useMutation({
    mutationFn: updateDashboardPreferences,
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["dashboard"] })
    }
  })
  const storedSortColumn = sortValue(payload.preferences.sort, "column")
  const storedSortDirection = sortValue(payload.preferences.sort, "direction")
  const queueSortOutsideLanding = payload.subject === "job" && storedSortColumn === "landing_queue_position" && !payload.landing_queue.visible
  const effectiveSortColumn = queueSortOutsideLanding ? "created_at" : storedSortColumn
  const effectiveSortDirection = queueSortOutsideLanding ? "desc" : storedSortDirection
  const [queueSortResetRequested, setQueueSortResetRequested] = useState(false)

  useEffect(() => {
    if (!queueSortOutsideLanding) {
      if (queueSortResetRequested) setQueueSortResetRequested(false)
      return
    }
    if (queueSortResetRequested || updateSort.isPending) return

    setQueueSortResetRequested(true)
    updateSort.mutate({
      subject: payload.subject,
      active_smart_folder_id: payload.active_smart_folder_id,
      sort_column: "created_at",
      sort_direction: "desc"
    })
  }, [payload.active_smart_folder_id, payload.subject, queueSortOutsideLanding, queueSortResetRequested, updateSort])

  const sortState: DashboardSortState = {
    column: effectiveSortColumn || payload.controls.sort_columns[0] || "title",
    direction: effectiveSortDirection || "desc",
    pending: updateSort.isPending,
    sortableColumns: payload.controls.sort_columns,
    onSort: (column) => {
      const sortColumn = sortableColumnFor(payload.subject, column)
      if (!sortColumn || !payload.controls.sort_columns.includes(sortColumn)) return

      const currentColumn = effectiveSortColumn || payload.controls.sort_columns[0] || "title"
      const currentDirection = effectiveSortDirection || "desc"
      const nextDirection = currentColumn === sortColumn && currentDirection === "asc" ? "desc" : "asc"
      updateSort.mutate({
        subject: payload.subject,
        active_smart_folder_id: payload.active_smart_folder_id,
        sort_column: sortColumn,
        sort_direction: nextDirection
      })
    }
  }

  if (payload.view === "kanban") return <DashboardKanban payload={payload} prefix={prefix} setupStatus={setupStatus} />

  if ((payload.items ?? []).length === 0) {
    if (payload.total === 0 && payload.counts[`${payload.subject}s` as keyof DashboardPayload["counts"]] === 0) {
      const emptyState = dashboardEmptyState(payload, t)
      return (
        <OnboardingEmptyState
          fallbackActionPath={emptyState.actionPath}
          fallbackActionText={emptyState.actionText}
          fallbackDescription={emptyState.description}
          fallbackTitle={emptyState.title}
          prefix={prefix}
          setupStatus={setupStatus}
        />
      )
    }

    return <div className="rounded border border-gray-200 bg-white p-6 text-sm text-gray-500 dark:border-gray-700 dark:bg-gray-900 dark:text-gray-400">{t("no_match", { subject: subjectLabel(payload.subject, 2) })}</div>
  }

  const columns = dashboardVisibleColumns(payload)
  const items = payload.items ?? []
  if (payload.subject === "job") return <JobsDashboardTable columns={columns} items={items.filter((item): item is DashboardJobItem => item.type === "job")} landingQueueEntries={payload.landing_queue.entries ?? []} prefix={prefix} sortState={sortState} t={t} />
  if (payload.subject === "workflow") return <WorkflowsTable columns={columns} items={items.filter((item): item is DashboardWorkflowItem => item.type === "workflow")} prefix={prefix} sortState={sortState} />

  return <EpicsTable columns={epicTableColumns(columns)} items={items.filter((item): item is DashboardEpicItem => item.type === "epic")} prefix={prefix} sortState={sortState} />
}

function EpicsTable({ items, columns, prefix, sortState }: { items: DashboardEpicItem[]; columns: string[]; prefix: string; sortState: DashboardSortState }) {
  const { t } = useT("dashboard")
  const [selectedIds, setSelectedIds] = useState<Set<number>>(() => new Set())
  const visibleIds = useMemo(() => items.map((item) => item.id), [items])
  const selectedArray = useMemo(() => Array.from(selectedIds), [selectedIds])
  const allSelected = visibleIds.length > 0 && visibleIds.every((id) => selectedIds.has(id))
  const isDesktop = useMediaQuery("(min-width: 1024px)", true)

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
      <BulkEpicActions selectedIds={selectedArray} onClear={() => setSelectedIds(new Set())} />
      {isDesktop ? (
        <div className="overflow-x-auto rounded border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-900">
          <table className="min-w-full divide-y divide-gray-200 text-sm dark:divide-gray-700">
            <thead className="bg-gray-50 text-left text-xs font-semibold uppercase text-gray-500 dark:bg-gray-800 dark:text-gray-400">
              <tr>
                {columns.map((column) => (
                  <th aria-sort={columnAriaSort("epic", column, sortState)} className={column === "checkbox" ? "w-10 px-4 py-2" : "px-4 py-2"} key={column}>
                    {column === "checkbox" ? <input aria-label={t("select_all_epics")} checked={allSelected} onChange={toggleAll} type="checkbox" /> : <SortableColumnHeader column={column} sortState={sortState} subject="epic" />}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100 dark:divide-gray-800">
              {items.map((epic) => (
                <tr key={epic.id}>
                  {columns.map((column) => <EpicCell column={column} epic={epic} key={column} onToggleOne={toggleOne} prefix={prefix} selected={selectedIds.has(epic.id)} />)}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : (
        <MobileEpicsList items={items} onToggleOne={toggleOne} prefix={prefix} selectedIds={selectedIds} />
      )}
    </div>
  )
}

function BulkEpicActions({ selectedIds, onClear }: { selectedIds: number[]; onClear: () => void }) {
  const { t } = useT("dashboard")
  const queryClient = useQueryClient()
  const [notice, setNotice] = useState<string | null>(null)
  const action = useMutation({
    mutationFn: (bulkAction: DashboardBulkEpicAction) => bulkDashboardEpics({ epic_ids: selectedIds, bulk_action: bulkAction }),
    onSuccess: (payload) => {
      setNotice(payload.message)
      onClear()
      void queryClient.invalidateQueries({ queryKey: ["dashboard"] })
    }
  })
  const disabled = selectedIds.length === 0 || action.isPending

  function run(bulkAction: DashboardBulkEpicAction) {
    setNotice(null)
    action.mutate(bulkAction)
  }

  if (selectedIds.length === 0) {
    return <NoticeToast message={notice} onDismiss={() => setNotice(null)} />
  }

  return (
    <div className="flex flex-wrap items-center justify-between gap-3 rounded border border-gray-200 bg-gray-50 px-3 py-2 text-sm dark:border-gray-700 dark:bg-gray-900">
      <div>
        <span className="font-medium text-gray-900 dark:text-gray-100">{t("selected_count", { count: selectedIds.length })}</span>
        <NoticeToast message={notice} onDismiss={() => setNotice(null)} />
        {action.isError ? <span className="ml-3 text-red-700 dark:text-red-300" role="alert">{errorMessage(action.error, t("bulk_action_error"))}</span> : null}
      </div>
      <div className="flex flex-wrap gap-2">
        <button className={bulkButtonClass(disabled)} disabled={disabled} onClick={() => run("start")} type="button">{t("move_to_in_progress")}</button>
      </div>
    </div>
  )
}

function MobileEpicsList({ items, selectedIds, onToggleOne, prefix }: { items: DashboardEpicItem[]; selectedIds: Set<number>; onToggleOne: (id: number) => void; prefix: string }) {
  return (
    <div className="rounded border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-900">
      <div className="divide-y divide-gray-100 dark:divide-gray-800">
        {items.map((epic) => <MobileEpicRow epic={epic} key={epic.id} onToggleOne={onToggleOne} prefix={prefix} selected={selectedIds.has(epic.id)} />)}
      </div>
    </div>
  )
}

function MobileEpicRow({ epic, selected, onToggleOne, prefix }: { epic: DashboardEpicItem; selected: boolean; onToggleOne: (id: number) => void; prefix: string }) {
  const { t } = useT("dashboard")
  return (
    <article aria-label={`${epic.display_number} ${epic.title}`} className="grid grid-cols-[auto_minmax(0,1fr)] gap-3 px-4 py-3 text-gray-700 dark:text-gray-200">
      <input aria-label={t("select_item", { title: epic.title })} checked={selected} className="mt-1" onChange={() => onToggleOne(epic.id)} type="checkbox" />
      <div className="min-w-0">
        <div className="mb-1">
          <NeutralStatePill state={epic.state} />
          <EpicStuckBadge stuck={epic.stuck} />
          <EpicProgressBar epic={epic} />
        </div>
        <div className="flex flex-wrap items-baseline gap-x-2 gap-y-1">
          <SlugHoverCard id={epic.id} kind="epic">
            <span className="font-mono text-xs font-semibold uppercase tracking-wide text-gray-500 dark:text-gray-400">{epic.display_number}</span>
          </SlugHoverCard>
          <Link aria-label={`${epic.display_number} ${epic.title}`} className="rounded-sm text-sm font-semibold leading-snug text-blue-600 underline focus:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 dark:text-blue-300" to={withRoutePrefix(epic.paths.epic_path, prefix)}>{epic.title}</Link>
        </div>
        {compactText(epic.description) ? <p className="mt-1 line-clamp-2 text-sm leading-snug text-gray-500 dark:text-gray-400">{compactText(epic.description)}</p> : null}
        <div className="mt-1 flex flex-wrap gap-x-2 gap-y-1 text-xs text-gray-500 dark:text-gray-400">
          <RepositorySlugLink prefix={prefix} repository={epic.repository} />
          <OwnerBadge badge={epic.owner_badge} />
        </div>
      </div>
    </article>
  )
}

function EpicCell({ epic, column, selected, onToggleOne, prefix }: { epic: DashboardEpicItem; column: string; selected: boolean; onToggleOne: (id: number) => void; prefix: string }) {
  const { t } = useT("dashboard")
  if (column === "checkbox") {
    return <td className="px-4 py-3 align-top"><input aria-label={t("select_item", { title: epic.title })} checked={selected} onChange={() => onToggleOne(epic.id)} type="checkbox" /></td>
  }
  if (column === "epic") {
    return (
      <td className="max-w-md px-4 py-3">
        <Link className="font-medium text-blue-600 hover:underline dark:text-blue-300" to={withRoutePrefix(epic.paths.epic_path, prefix)}>{epic.title}</Link>
        <div className="mt-1 font-mono text-xs text-gray-500 dark:text-gray-400">
          <SlugHoverCard id={epic.id} kind="epic">{epic.display_number}</SlugHoverCard>
        </div>
      </td>
    )
  }
  if (column === "state") {
    return (
      <td className="px-4 py-3">
        <div className="flex flex-wrap gap-1">
          <NeutralStatePill state={epic.state} />
          <EpicStuckBadge stuck={epic.stuck} />
          <EpicProgressBar epic={epic} />
        </div>
      </td>
    )
  }
  if (column === "owner") return <td className="px-4 py-3 text-xs text-gray-600 dark:text-gray-300"><OwnerBadge badge={epic.owner_badge} /></td>
  if (column === "repository") {
    return <td className="px-4 py-3"><RepositorySlugLink className="font-mono text-xs text-gray-600 hover:text-blue-700 hover:underline dark:text-gray-300 dark:hover:text-blue-300" prefix={prefix} repository={epic.repository} /></td>
  }
  if (column === "updated") return <TimestampCell value={epic.updated_at} />

  return <TimestampCell value={epicDateValue(epic, column)} />
}

function WorkflowsTable({ items, columns, prefix, sortState }: { items: DashboardWorkflowItem[]; columns: string[]; prefix: string; sortState: DashboardSortState }) {
  const isDesktop = useMediaQuery("(min-width: 1024px)", true)

  if (!isDesktop) return <MobileWorkflowsList items={items} prefix={prefix} />

  return (
    <div className="overflow-x-auto rounded border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-900">
      <table className="min-w-full divide-y divide-gray-200 text-sm dark:divide-gray-700">
        <thead className="bg-gray-50 text-left text-xs font-semibold uppercase text-gray-500 dark:bg-gray-800 dark:text-gray-400">
          <tr>
            {columns.map((column) => <th aria-sort={columnAriaSort("workflow", column, sortState)} className="px-4 py-2" key={column}><SortableColumnHeader column={column} sortState={sortState} subject="workflow" /></th>)}
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-100 dark:divide-gray-800">
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

function MobileWorkflowsList({ items, prefix }: { items: DashboardWorkflowItem[]; prefix: string }) {
  return (
    <div className="rounded border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-900">
      <div className="divide-y divide-gray-100 dark:divide-gray-800">
        {items.map((workflow) => <MobileWorkflowRow key={workflow.id} prefix={prefix} workflow={workflow} />)}
      </div>
    </div>
  )
}

function MobileWorkflowRow({ workflow, prefix }: { prefix: string; workflow: DashboardWorkflowItem }) {
  const { t } = useT("dashboard")
  const startedAt = workflow.started_at || workflow.created_at
  const finishedAt = workflow.finished_at || workflow.cleaned_up_at
  const slug = workflowLabel(workflow)

  return (
    <Link aria-label={`${slug} ${workflow.job.title}`} className="grid grid-cols-[7.25rem_minmax(0,1fr)] gap-3 px-4 py-3 text-gray-700 hover:bg-gray-50 hover:text-gray-900 focus:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 dark:text-gray-200 dark:hover:bg-gray-800 dark:hover:text-white" to={withRoutePrefix(workflow.path, prefix)}>
      <div className="pt-1">
        <StatusPill state={workflow.state} />
      </div>
      <div className="min-w-0">
        <div className="flex flex-wrap items-baseline gap-x-2 gap-y-1">
          <span className="font-mono text-xs font-semibold uppercase tracking-wide text-gray-500 dark:text-gray-400">{slug}</span>
          <span className="text-sm font-semibold leading-snug text-blue-600 underline dark:text-blue-300">{workflow.job.title}</span>
        </div>
        <div className="mt-1 font-mono text-xs text-gray-500 dark:text-gray-400">{workflow.job.repository.slug}</div>
        <div className="mt-2 flex flex-wrap gap-x-3 gap-y-1 text-xs text-gray-500 dark:text-gray-400">
          <span>{workflow.trigger_kind}</span>
          <span>{workflow.agent_provider}</span>
          <OwnerBadge badge={workflow.job.owner_badge} />
          {startedAt ? <span>{t("started_at", { date: formatDate(startedAt) })}</span> : null}
          {finishedAt ? <span>{t("finished_at", { date: formatDate(finishedAt) })}</span> : null}
        </div>
      </div>
    </Link>
  )
}

function WorkflowCell({ workflow, column, prefix }: { workflow: DashboardWorkflowItem; column: string; prefix: string }) {
  if (column === "workflow" || column === "title") {
    return (
      <td className="px-4 py-3 font-medium">
        <Link className="text-blue-600 hover:underline dark:text-blue-300" to={withRoutePrefix(workflow.path, prefix)}>{workflowLabel(workflow)}</Link>
      </td>
    )
  }
  if (column === "state") return <td className="px-4 py-3"><StatusPill state={workflow.state} /></td>
  if (column === "job") {
    return (
      <td className="max-w-md px-4 py-3">
        <Link className="font-medium text-blue-600 hover:underline dark:text-blue-300" to={withRoutePrefix(workflow.job.path, prefix)}>{workflow.job.title}</Link>
        <div className="mt-1 flex flex-wrap gap-1 text-xs text-gray-500 dark:text-gray-400">
          <RepositorySlugLink prefix={prefix} repository={workflow.job.repository} />
          <OwnerBadge badge={workflow.job.owner_badge} />
        </div>
      </td>
    )
  }
  if (column === "trigger") return <td className="px-4 py-3 text-gray-700 dark:text-gray-200">{workflow.trigger_kind}</td>
  if (column === "agent") return <td className="px-4 py-3 text-gray-700 dark:text-gray-200">{workflow.agent_provider}</td>
  if (column === "started") return <TimestampCell value={workflow.started_at || workflow.created_at} />
  if (column === "finished") return <TimestampCell value={workflow.finished_at} />

  return <TimestampCell value={workflowDateValue(workflow, column)} />
}

function Pagination({ payload, pathname, search }: { payload: DashboardPayload; pathname: string; search: string }) {
  const { t } = useT("dashboard")
  if (payload.total_pages <= 1) return null

  const firstItem = (payload.page - 1) * payload.per_page + 1
  const lastItem = Math.min(payload.page * payload.per_page, payload.total)

  return (
    <div className="flex items-center justify-between text-sm text-gray-600 dark:text-gray-300">
      <span>{t("showing_pagination", { first: firstItem, last: lastItem, total: payload.total })}</span>
      <div className="flex gap-2">
        {payload.page > 1 ? (
          <Link className="rounded border border-gray-300 px-3 py-1 hover:bg-gray-50 dark:border-gray-700 dark:hover:bg-gray-800" to={pageLink(pathname, search, payload.page - 1)}>{t("previous")}</Link>
        ) : (
          <span className="rounded border border-gray-200 px-3 py-1 text-gray-300 dark:border-gray-800 dark:text-gray-600">{t("previous")}</span>
        )}
        {payload.page < payload.total_pages ? (
          <Link className="rounded border border-gray-300 px-3 py-1 hover:bg-gray-50 dark:border-gray-700 dark:hover:bg-gray-800" to={pageLink(pathname, search, payload.page + 1)}>{t("next")}</Link>
        ) : (
          <span className="rounded border border-gray-200 px-3 py-1 text-gray-300 dark:border-gray-800 dark:text-gray-600">{t("next")}</span>
        )}
      </div>
    </div>
  )
}

function DashboardError({ error }: { error: Error }) {
  const { t } = useT("dashboard")
  return (
    <main aria-label={t("title")} className="p-6">
      <p className="text-sm text-red-700 dark:text-red-300">{error instanceof ApiError ? error.message : t("load_error")}</p>
    </main>
  )
}

