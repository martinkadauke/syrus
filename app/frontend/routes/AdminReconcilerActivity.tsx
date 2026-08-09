import { RelativeTimestamp } from "../components/RelativeTimestamp"
import { fetchAdminReconcilerActivity, type AdminReconcilerActivityPayload, type ReconcilerActivityEvent } from "../api/adminReconcilerActivity"
import { routePrefix, withRoutePrefix } from "../lib/routing"
import { useQuery } from "@tanstack/react-query"
import type { FormEvent, ReactNode } from "react"
import { Link, useLocation, useNavigate, useSearchParams } from "react-router-dom"
import { usePageTitle } from "../hooks/usePageTitle"
import { useT } from "../hooks/useT"

const POLL_INTERVAL_MS = 30_000

export function AdminReconcilerActivity() {
  const { t } = useT("admin")
  usePageTitle(t("page_title_reconciler_activity"))
  const location = useLocation()
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()
  const prefix = routePrefix(location.pathname)
  const activity = useQuery({
    queryKey: ["admin", "reconciler_activity", location.search],
    queryFn: ({ signal }) => fetchAdminReconcilerActivity(location.search, signal),
    refetchInterval: POLL_INTERVAL_MS
  })

  function applyFilters(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const form = new FormData(event.currentTarget)
    const next = new URLSearchParams()
    for (const key of ["event_type", "job_id", "workflow_id", "run_id"]) {
      const value = String(form.get(key) || "").trim()
      if (value.length > 0) next.set(key, value)
    }
    navigate(`${location.pathname}${next.toString() ? `?${next}` : ""}`)
  }

  return (
    <main aria-label={t("reconciler_activity.aria")} className="mx-auto max-w-[96rem] space-y-6 p-6">
      <header className="flex items-end justify-between gap-4 border-b border-gray-200 pb-4 dark:border-gray-700">
        <div>
          <p className="text-xs font-medium uppercase text-gray-500 dark:text-gray-400">{t("section_label")}</p>
          <h1 className="mt-1 text-2xl font-semibold text-gray-900 dark:text-gray-100">{t("reconciler_activity.heading")}</h1>
        </div>
        <button
          className="inline-flex shrink-0 items-center justify-center rounded border border-gray-300 bg-white px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 disabled:cursor-not-allowed disabled:text-gray-400 dark:border-gray-600 dark:bg-gray-900 dark:text-gray-200 dark:hover:bg-gray-800 dark:disabled:text-gray-500"
          disabled={activity.isFetching}
          onClick={() => void activity.refetch()}
          type="button"
        >
          {activity.isFetching ? t("reconciler_activity.refreshing") : t("reconciler_activity.refresh")}
        </button>
      </header>

      <form className="grid gap-3 rounded border border-gray-200 bg-white p-4 text-sm dark:border-gray-700 dark:bg-gray-900 sm:grid-cols-2 lg:grid-cols-5" onSubmit={applyFilters}>
        <label className="space-y-1">
          <span className="block text-xs font-medium uppercase text-gray-500 dark:text-gray-400">{t("reconciler_activity.filter_event_type")}</span>
          <select className={inputClass()} defaultValue={searchParams.get("event_type") || ""} name="event_type">
            <option value="">{t("reconciler_activity.all_event_types")}</option>
            {(activity.data?.event_types || []).map((type) => <option key={type} value={type}>{type}</option>)}
          </select>
        </label>
        <TextFilter defaultValue={searchParams.get("job_id") || ""} label={t("reconciler_activity.filter_job")} name="job_id" />
        <TextFilter defaultValue={searchParams.get("workflow_id") || ""} label={t("reconciler_activity.filter_workflow")} name="workflow_id" />
        <TextFilter defaultValue={searchParams.get("run_id") || ""} label={t("reconciler_activity.filter_run")} name="run_id" />
        <div className="flex items-end gap-2">
          <button className="rounded bg-gray-900 px-3 py-2 font-medium text-white hover:bg-gray-800 dark:bg-gray-100 dark:text-gray-900 dark:hover:bg-gray-200" type="submit">{t("reconciler_activity.apply_filters")}</button>
          <Link className="rounded border border-gray-300 px-3 py-2 font-medium text-gray-700 hover:bg-gray-50 dark:border-gray-600 dark:text-gray-200 dark:hover:bg-gray-800" to={withRoutePrefix("/admin/reconciler_activity", prefix)}>{t("reconciler_activity.clear_filters")}</Link>
        </div>
      </form>

      <section className="rounded border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-900">
        {activity.isPending ? <PanelMessage>{t("reconciler_activity.loading")}</PanelMessage> : null}
        {activity.isError ? <PanelMessage tone="error">{t("reconciler_activity.error_load")}</PanelMessage> : null}
        {activity.isSuccess ? <ActivityTable payload={activity.data} prefix={prefix} /> : null}
      </section>
    </main>
  )
}

function TextFilter({ defaultValue, label, name }: { defaultValue: string; label: string; name: string }) {
  return (
    <label className="space-y-1">
      <span className="block text-xs font-medium uppercase text-gray-500 dark:text-gray-400">{label}</span>
      <input className={inputClass()} defaultValue={defaultValue} inputMode="numeric" name={name} />
    </label>
  )
}

function ActivityTable({ payload, prefix }: { payload: AdminReconcilerActivityPayload; prefix: string }) {
  const { t } = useT("admin")
  if (payload.events.length === 0) return <PanelMessage>{t("reconciler_activity.no_events")}</PanelMessage>

  return (
    <div>
      <div className="border-b border-gray-200 px-4 py-3 text-sm text-gray-600 dark:border-gray-700 dark:text-gray-300">
        {t("reconciler_activity.showing", { first: payload.pagination.first_item, last: payload.pagination.last_item, total: payload.pagination.total })}
      </div>
      <div className="overflow-x-auto">
        <table className="min-w-full divide-y divide-gray-200 text-sm dark:divide-gray-700">
          <thead className="bg-gray-50 text-left text-xs font-medium uppercase text-gray-500 dark:bg-gray-800 dark:text-gray-400">
            <tr>
              <th className="px-4 py-2">{t("reconciler_activity.col_time")}</th>
              <th className="px-4 py-2">{t("reconciler_activity.col_type")}</th>
              <th className="px-4 py-2">{t("reconciler_activity.col_context")}</th>
              <th className="px-4 py-2">{t("reconciler_activity.col_decision")}</th>
              <th className="px-4 py-2">{t("reconciler_activity.col_message")}</th>
              <th className="px-4 py-2">{t("reconciler_activity.col_source")}</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100 dark:divide-gray-800">
            {payload.events.map((event) => <ActivityRow event={event} key={event.id} prefix={prefix} />)}
          </tbody>
        </table>
      </div>
      <Pagination pagination={payload.pagination} prefix={prefix} />
    </div>
  )
}

function ActivityRow({ event, prefix }: { event: ReconcilerActivityEvent; prefix: string }) {
  return (
    <tr>
      <td className="whitespace-nowrap px-4 py-2 text-xs text-gray-500 dark:text-gray-400"><RelativeTimestamp value={event.occurred_at} /></td>
      <td className="px-4 py-2">
        <span className={`rounded px-1.5 py-0.5 font-mono text-xs ${severityClass(event.severity)}`}>{event.event_type}</span>
      </td>
      <td className="px-4 py-2 text-xs text-gray-600 dark:text-gray-300"><ContextLinks event={event} prefix={prefix} /></td>
      <td className="px-4 py-2 font-mono text-xs text-gray-600 dark:text-gray-300">{decisionLabel(event)}</td>
      <td className="max-w-3xl px-4 py-2 text-gray-700 dark:text-gray-200">
        <div>{event.message}</div>
        <details className="mt-1">
          <summary className="cursor-pointer text-xs text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200">details</summary>
          <pre className="mt-1 max-h-64 overflow-auto rounded bg-gray-50 p-2 text-xs text-gray-700 dark:bg-gray-950 dark:text-gray-300">{JSON.stringify(event.details, null, 2)}</pre>
        </details>
      </td>
      <td className="px-4 py-2 font-mono text-xs text-gray-500 dark:text-gray-400">{event.source}</td>
    </tr>
  )
}

function ContextLinks({ event, prefix }: { event: ReconcilerActivityEvent; prefix: string }) {
  const links: ReactNode[] = []
  if (event.job) links.push(<Link className={linkClass()} key="job" to={withRoutePrefix(event.job.path, prefix)}>{event.job.slug}</Link>)
  if (event.workflow) links.push(<Link className={linkClass()} key="workflow" to={withRoutePrefix(event.workflow.path, prefix)}>{event.workflow.slug}</Link>)
  if (event.run) links.push(<Link className={linkClass()} key="run" to={withRoutePrefix(event.run.path, prefix)}>Run #{event.run.id}</Link>)
  if (links.length === 0) return <span>-</span>

  return <span className="flex flex-wrap gap-x-2 gap-y-1">{links}</span>
}

function Pagination({ pagination, prefix }: { pagination: AdminReconcilerActivityPayload["pagination"]; prefix: string }) {
  const { t } = useT("admin")
  if (pagination.total_pages <= 1) return null

  return (
    <nav aria-label={t("reconciler_activity.aria_pagination")} className="flex items-center justify-between border-t border-gray-200 px-4 py-3 text-sm text-gray-600 dark:border-gray-700 dark:text-gray-300">
      <span>{t("reconciler_activity.page_of", { page: pagination.page, total: pagination.total_pages })}</span>
      <div className="flex items-center gap-2">
        {pagination.previous_path ? <Link className={paginationLinkClass()} to={withRoutePrefix(pagination.previous_path, prefix)}>{t("reconciler_activity.previous")}</Link> : <span className={disabledPaginationClass()}>{t("reconciler_activity.previous")}</span>}
        {pagination.next_path ? <Link className={paginationLinkClass()} to={withRoutePrefix(pagination.next_path, prefix)}>{t("reconciler_activity.next")}</Link> : <span className={disabledPaginationClass()}>{t("reconciler_activity.next")}</span>}
      </div>
    </nav>
  )
}

function PanelMessage({ children, tone = "muted" }: { children: ReactNode; tone?: "muted" | "error" }) {
  return <div className={`p-4 text-sm ${tone === "error" ? "text-red-700 dark:text-red-300" : "text-gray-600 dark:text-gray-300"}`}>{children}</div>
}

function decisionLabel(event: ReconcilerActivityEvent) {
  return [event.issue_kind, event.repair_action, event.repair_status].filter(Boolean).join(" · ") || "-"
}

function severityClass(severity: string) {
  if (severity === "alarm") return "bg-red-100 text-red-700 dark:bg-red-950/60 dark:text-red-300"
  if (severity === "error") return "bg-red-100 text-red-700 dark:bg-red-950/60 dark:text-red-300"
  if (severity === "warn") return "bg-amber-100 text-amber-700 dark:bg-amber-950/60 dark:text-amber-300"
  return "bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-300"
}

function inputClass() {
  return "block h-9 w-full rounded border border-gray-300 bg-white px-2 text-sm text-gray-900 focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500 dark:border-gray-600 dark:bg-gray-950 dark:text-gray-100"
}

function linkClass() {
  return "text-blue-600 underline hover:no-underline dark:text-blue-300"
}

function paginationLinkClass() {
  return "rounded border border-gray-300 px-3 py-1 text-gray-700 hover:bg-gray-50 dark:border-gray-700 dark:text-gray-200 dark:hover:bg-gray-800"
}

function disabledPaginationClass() {
  return "rounded border border-gray-200 px-3 py-1 text-gray-400 dark:border-gray-800 dark:text-gray-600"
}
