import { useQuery } from "@tanstack/react-query"
import type { ReactNode } from "react"
import { Link, useLocation } from "react-router-dom"
import { fetchAdminStuck, type StuckItem } from "../api/adminStuck"

const POLL_INTERVAL_MS = 30_000

export function AdminStuck() {
  const location = useLocation()
  const prefix = routePrefix(location.pathname)
  const stuck = useQuery({
    queryKey: ["admin", "stuck"],
    queryFn: fetchAdminStuck,
    refetchInterval: POLL_INTERVAL_MS
  })

  return (
    <main aria-label="Admin stuck items" className="mx-auto max-w-7xl space-y-6 p-6">
      <header className="flex flex-col gap-4 border-b border-gray-200 pb-4 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="text-xs font-medium uppercase text-gray-500">Admin</p>
          <h1 className="mt-1 text-2xl font-semibold text-gray-900">Stuck Things</h1>
        </div>
        <button
          className="inline-flex items-center justify-center rounded border border-gray-300 bg-white px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 disabled:cursor-not-allowed disabled:text-gray-400"
          disabled={stuck.isFetching}
          onClick={() => void stuck.refetch()}
          type="button"
        >
          {stuck.isFetching ? "Refreshing..." : "Refresh"}
        </button>
      </header>

      <section className="rounded border border-gray-200 bg-white">
        {stuck.isPending ? <PanelMessage>Loading stuck items...</PanelMessage> : null}
        {stuck.isError ? <PanelMessage tone="error">Unable to load stuck items.</PanelMessage> : null}
        {stuck.isSuccess ? <StuckTable items={stuck.data.items} prefix={prefix} /> : null}
      </section>
    </main>
  )
}

function StuckTable({ items, prefix }: { items: StuckItem[]; prefix: string }) {
  if (items.length === 0) {
    return (
      <div className="bg-emerald-50 p-6 text-sm text-emerald-800">
        Nothing stuck. Reaper, pruner, and worker pool are all keeping up.
      </div>
    )
  }

  return (
    <div className="overflow-x-auto">
      <table className="min-w-full divide-y divide-gray-200 text-sm">
        <thead className="bg-gray-50 text-left text-xs font-medium uppercase text-gray-500">
          <tr>
            <th className="px-4 py-2">Severity</th>
            <th className="px-4 py-2">Kind</th>
            <th className="px-4 py-2">Detail</th>
            <th className="px-4 py-2">Run / Step / Workflow</th>
            <th className="px-4 py-2">Age</th>
            <th className="px-4 py-2 text-right">Links</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-100">
          {items.map((item) => (
            <tr key={`${item.kind}-${item.run_id || "none"}-${item.workflow_id || "none"}`}>
              <td className="px-4 py-2">
                <span className={`rounded px-1.5 py-0.5 font-mono text-xs uppercase ${severityClass(item.severity)}`}>
                  {item.severity}
                </span>
              </td>
              <td className="px-4 py-2 font-mono text-xs text-gray-700">{item.kind}</td>
              <td className="px-4 py-2 text-gray-700">{item.detail}</td>
              <td className="px-4 py-2 text-xs text-gray-600">{contextLabel(item)}</td>
              <td className="px-4 py-2 text-xs text-gray-500">{item.age_label}</td>
              <td className="space-x-3 px-4 py-2 text-right text-xs">
                {item.job_id ? <Link className="text-blue-600 underline hover:no-underline" to={withRoutePrefix(`/jobs/${item.job_id}`, prefix)}>Job</Link> : null}
                {item.run_id && item.has_transcript ? (
                  <Link className="text-indigo-600 underline hover:no-underline" to={withRoutePrefix(`/admin/runs/${item.run_id}/transcript`, prefix)}>Transcript</Link>
                ) : null}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

function PanelMessage({ children, tone = "muted" }: { children: ReactNode; tone?: "muted" | "error" }) {
  return <div className={`p-4 text-sm ${tone === "error" ? "text-red-700" : "text-gray-600"}`}>{children}</div>
}

function routePrefix(pathname: string) {
  return pathname.startsWith("/app-shell") ? "/app-shell" : ""
}

function withRoutePrefix(path: string, prefix: string) {
  if (!prefix || path.startsWith(prefix)) return path
  if (!path.startsWith("/")) return path

  return `${prefix}${path}`
}

function severityClass(severity: string) {
  return severity === "alarm" ? "bg-red-100 text-red-700" : "bg-amber-100 text-amber-700"
}

function contextLabel(item: StuckItem) {
  const parts = []
  if (item.run_id) parts.push(`Run #${item.run_id}`)
  if (item.workflow_trigger_kind) parts.push(item.workflow_trigger_kind)
  if (item.step_kind) parts.push(`step ${item.step_kind}`)
  if (parts.length === 0 && item.workflow_id) parts.push(`Workflow #${item.workflow_id}`)

  return parts.join(" · ") || "-"
}
