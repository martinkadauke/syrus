import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"
import type { ReactNode } from "react"
import { Link, useLocation, useParams, useSearchParams } from "react-router-dom"
import { ApiError } from "../api/client"
import {
  fetchAdminProcess,
  fetchAdminProcesses,
  killAdminProcess,
  type ProcessStateFilter,
  type SpawnedProcessPayload
} from "../api/adminProcesses"

const stateOptions: Array<{ label: string; value?: ProcessStateFilter }> = [
  { label: "Active + recent" },
  { label: "Running", value: "running" },
  { label: "Finished", value: "finished" },
  { label: "All", value: "all" }
]

export function AdminProcessesIndex() {
  const [searchParams] = useSearchParams()
  const state = processState(searchParams.get("state"))
  const location = useLocation()
  const basePath = location.pathname.startsWith("/app-shell") ? "/app-shell/admin/processes" : "/admin/processes"
  const processes = useQuery({
    queryKey: ["admin", "processes", { state }],
    queryFn: () => fetchAdminProcesses({ state })
  })

  return (
    <main aria-label="Admin processes" className="mx-auto max-w-7xl space-y-6 p-6">
      <header className="border-b border-gray-200 pb-4">
        <p className="text-xs font-medium uppercase text-gray-500">Admin</p>
        <h1 className="mt-1 text-2xl font-semibold text-gray-900">Processes</h1>
      </header>

      <nav aria-label="Process state filters" className="flex flex-wrap gap-2">
        {stateOptions.map((option) => {
          const active = option.value === state || (!option.value && !state)
          const to = option.value ? `${basePath}?state=${option.value}` : basePath

          return (
            <Link
              className={`rounded border px-3 py-1.5 text-sm ${
                active ? "border-gray-900 bg-gray-900 text-white" : "border-gray-300 bg-white text-gray-700 hover:bg-gray-50"
              }`}
              key={option.label}
              to={to}
            >
              {option.label}
            </Link>
          )
        })}
      </nav>

      <section className="rounded border border-gray-200 bg-white">
        {processes.isPending ? <PanelMessage>Loading processes...</PanelMessage> : null}
        {processes.isError ? <ProcessError error={processes.error} /> : null}
        {processes.isSuccess ? (
          <>
            <div className="border-b border-gray-200 px-4 py-3 text-sm text-gray-600">
              {processes.data.running_total} running · {processes.data.processes.length} shown
            </div>
            <ProcessesTable basePath={basePath} processes={processes.data.processes} />
          </>
        ) : null}
      </section>
    </main>
  )
}

export function AdminProcessDetail() {
  const params = useParams()
  const id = params.id || ""
  const location = useLocation()
  const basePath = location.pathname.startsWith("/app-shell") ? "/app-shell/admin/processes" : "/admin/processes"
  const process = useQuery({
    queryKey: ["admin", "processes", id],
    queryFn: () => fetchAdminProcess(id),
    enabled: id.length > 0
  })

  return (
    <main aria-label="Admin process detail" className="mx-auto max-w-5xl space-y-6 p-6">
      <header className="border-b border-gray-200 pb-4">
        <Link className="text-sm text-blue-600 underline hover:no-underline" to={basePath}>Processes</Link>
        <h1 className="mt-2 text-2xl font-semibold text-gray-900">Process {id ? `#${id}` : ""}</h1>
      </header>

      <section className="rounded border border-gray-200 bg-white">
        {process.isPending ? <PanelMessage>Loading process...</PanelMessage> : null}
        {process.isError ? <ProcessError error={process.error} /> : null}
        {process.isSuccess ? <ProcessDetail process={process.data} /> : null}
      </section>
    </main>
  )
}

function ProcessesTable({ processes, basePath }: { processes: SpawnedProcessPayload[]; basePath: string }) {
  if (processes.length === 0) return <PanelMessage>No processes match this filter.</PanelMessage>

  return (
    <div className="overflow-x-auto">
      <table className="min-w-full divide-y divide-gray-200 text-sm">
        <thead className="bg-gray-50 text-left text-xs font-medium uppercase text-gray-500">
          <tr>
            <th className="px-3 py-2">Kind</th>
            <th className="px-3 py-2">Command</th>
            <th className="px-3 py-2">Host / PID</th>
            <th className="px-3 py-2">Started</th>
            <th className="px-3 py-2">Last chunk</th>
            <th className="px-3 py-2">Duration</th>
            <th className="px-3 py-2">Outcome</th>
            <th className="px-3 py-2 text-right">Actions</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-100">
          {processes.map((process) => (
            <tr className={process.stale ? "bg-amber-50" : ""} key={process.id}>
              <td className="px-3 py-2 align-top">
                <span className="rounded bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-700">{process.kind}</span>
              </td>
              <td className="max-w-md truncate px-3 py-2 align-top font-mono text-xs text-gray-700" title={process.command}>{process.command}</td>
              <td className="px-3 py-2 align-top font-mono text-xs text-gray-600">
                {process.hostname || "-"}
                {process.pid ? <div className="text-gray-500">pid {process.pid}</div> : null}
              </td>
              <td className="whitespace-nowrap px-3 py-2 align-top text-xs text-gray-700">{formatDate(process.started_at)}</td>
              <td className="whitespace-nowrap px-3 py-2 align-top text-xs text-gray-700">
                {formatDate(process.last_chunk_at)}
                {process.stale ? <span className="ml-1 rounded bg-amber-200 px-1 text-[0.65rem] font-semibold uppercase text-amber-900">stale</span> : null}
              </td>
              <td className="px-3 py-2 align-top text-xs text-gray-700">{formatDuration(process.duration_s)}</td>
              <td className="px-3 py-2 align-top text-xs"><Outcome process={process} /></td>
              <td className="space-x-3 whitespace-nowrap px-3 py-2 text-right align-top text-xs">
                <Link className="text-blue-600 underline hover:no-underline" to={`${basePath}/${process.id}`}>Detail</Link>
                <KillButton process={process} />
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

function ProcessDetail({ process }: { process: SpawnedProcessPayload }) {
  return (
    <div className="space-y-5 p-4">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <div className="flex items-center gap-2">
            <h2 className="text-lg font-semibold text-gray-900">#{process.id}</h2>
            <span className="rounded bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-700">{process.kind}</span>
          </div>
          <p className="mt-2 break-all font-mono text-xs text-gray-600">{process.command}</p>
        </div>
        <KillButton process={process} />
      </div>

      <dl className="grid grid-cols-1 gap-x-6 gap-y-3 text-sm sm:grid-cols-[10rem_1fr]">
        <dt className="text-gray-500">Hostname</dt>
        <dd className="font-mono text-gray-900">{process.hostname || "-"}</dd>
        <dt className="text-gray-500">PID / PGID</dt>
        <dd className="font-mono text-gray-900">{process.pid || "-"} / {process.pgid || "-"}</dd>
        <dt className="text-gray-500">Workdir</dt>
        <dd className="break-all font-mono text-gray-900">{process.workdir || "-"}</dd>
        <dt className="text-gray-500">Started</dt>
        <dd>{formatDate(process.started_at)}</dd>
        <dt className="text-gray-500">Last chunk</dt>
        <dd>{formatDate(process.last_chunk_at)} {process.stale ? <span className="rounded bg-amber-200 px-1 text-[0.65rem] font-semibold uppercase text-amber-900">stale</span> : null}</dd>
        <dt className="text-gray-500">Finished</dt>
        <dd>{formatDate(process.finished_at)}</dd>
        <dt className="text-gray-500">Duration</dt>
        <dd>{formatDuration(process.duration_s)}</dd>
        <dt className="text-gray-500">Outcome</dt>
        <dd><Outcome process={process} /></dd>
        <dt className="text-gray-500">Wall timeout</dt>
        <dd>{formatDuration(process.wall_timeout_s)}</dd>
        <dt className="text-gray-500">Silent timeout</dt>
        <dd>{formatDuration(process.silent_timeout_s)}</dd>
        {process.run_id ? (
          <>
            <dt className="text-gray-500">Run</dt>
            <dd><a className="text-blue-600 underline hover:no-underline" href={`/admin/runs/${process.run_id}/transcript`}>#{process.run_id}</a></dd>
          </>
        ) : null}
        {process.workflow_id ? (
          <>
            <dt className="text-gray-500">Workflow</dt>
            <dd>#{process.workflow_id}</dd>
          </>
        ) : null}
        {process.kill_requested_at ? (
          <>
            <dt className="text-gray-500">Kill requested</dt>
            <dd>{formatDate(process.kill_requested_at)}</dd>
          </>
        ) : null}
      </dl>

      {process.host_metrics ? <HostMetrics metrics={process.host_metrics} /> : null}
    </div>
  )
}

function KillButton({ process }: { process: SpawnedProcessPayload }) {
  const queryClient = useQueryClient()
  const kill = useMutation({
    mutationFn: () => killAdminProcess(process.id),
    onSuccess: (updated) => {
      queryClient.setQueryData(["admin", "processes", String(process.id)], updated)
      void queryClient.invalidateQueries({ queryKey: ["admin", "processes"] })
    }
  })

  if (process.finished_at || process.kill_requested_at) return null

  return (
    <button
      className="inline-flex items-center rounded bg-red-600 px-2 py-0.5 text-xs font-medium text-white hover:bg-red-700 disabled:cursor-not-allowed disabled:bg-red-300"
      disabled={kill.isPending}
      onClick={() => kill.mutate()}
      type="button"
    >
      {kill.isPending ? "Killing..." : "Kill"}
    </button>
  )
}

function HostMetrics({ metrics }: { metrics: Record<string, unknown> }) {
  return (
    <div className="border-t border-gray-200 pt-4">
      <h3 className="text-sm font-semibold text-gray-700">Host metrics</h3>
      <dl className="mt-2 grid grid-cols-2 gap-x-4 gap-y-2 text-sm sm:grid-cols-4">
        {Object.entries(metrics).map(([key, value]) => (
          <div key={key}>
            <dt className="text-gray-500">{key}</dt>
            <dd className="font-mono text-gray-900">{String(value ?? "-")}</dd>
          </div>
        ))}
      </dl>
    </div>
  )
}

function Outcome({ process }: { process: SpawnedProcessPayload }) {
  if (process.finished_at) {
    return <span className="rounded bg-gray-100 px-2 py-0.5 font-medium text-gray-700">{process.outcome || "finished"}</span>
  }
  if (process.kill_requested_at) {
    return <span className="rounded bg-amber-100 px-2 py-0.5 font-medium text-amber-800">kill requested</span>
  }
  return <span className="rounded bg-blue-100 px-2 py-0.5 font-medium text-blue-800">running</span>
}

function ProcessError({ error }: { error: Error }) {
  const message = error instanceof ApiError ? error.message : "Unable to load process data."

  return <PanelMessage tone="error">{message}</PanelMessage>
}

function PanelMessage({ children, tone = "muted" }: { children: ReactNode; tone?: "muted" | "error" }) {
  return <div className={`p-4 text-sm ${tone === "error" ? "text-red-700" : "text-gray-600"}`}>{children}</div>
}

function processState(value: string | null): ProcessStateFilter | undefined {
  if (value === "running" || value === "finished" || value === "all") return value
  return undefined
}

function formatDate(value: string | null) {
  if (!value) return "-"

  return new Date(value).toLocaleString()
}

function formatDuration(value: number | null) {
  if (value == null) return "-"
  if (value < 60) return `${Math.round(value)}s`

  const minutes = Math.floor(value / 60)
  if (minutes < 60) return `${minutes}m`

  const hours = Math.floor(minutes / 60)
  return `${hours}h ${minutes % 60}m`
}
