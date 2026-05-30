import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"
import type { ReactNode } from "react"
import { useState } from "react"
import {
  clearGithubCache,
  fetchAdminConsole,
  reapStaleRuns,
  runConsoleCommand,
  type AdminConsolePayload,
  type ConsoleAction,
  type ConsoleCommand,
  type ConsoleSettings
} from "../api/adminConsole"
import { ApiError } from "../api/client"

export function AdminConsole() {
  const consoleQuery = useQuery({
    queryKey: ["admin", "console"],
    queryFn: fetchAdminConsole
  })

  return (
    <main aria-label="Admin console" className="mx-auto max-w-6xl space-y-6 p-6">
      <header className="border-b border-gray-200 pb-4">
        <p className="text-xs font-medium uppercase text-gray-500">Admin</p>
        <h1 className="mt-1 text-2xl font-semibold text-gray-900">Operator Console</h1>
      </header>

      {consoleQuery.isPending ? <PanelMessage>Loading console...</PanelMessage> : null}
      {consoleQuery.isError ? <ConsoleError error={consoleQuery.error} /> : null}
      {consoleQuery.isSuccess ? <ConsoleView payload={consoleQuery.data} /> : null}
    </main>
  )
}

function ConsoleView({ payload }: { payload: AdminConsolePayload }) {
  return (
    <>
      <section className="grid gap-4 md:grid-cols-2">
        <TogglePanel
          command={payload.settings.polling_paused ? "unpause_polling" : "pause_polling"}
          description="Stops recurring fan-out jobs from enqueueing per-Job pollers while leaving manual poll buttons available."
          label={payload.settings.polling_paused ? "Resume polling" : "Pause polling"}
          title="Polling"
          value={payload.settings.polling_paused ? "paused" : "running"}
          warning={payload.settings.polling_paused}
        />
        <TogglePanel
          command={payload.settings.runs_paused ? "unpause_runs" : "pause_runs"}
          description="Defers new RunJob work at perform time. Already-running Runs continue."
          label={payload.settings.runs_paused ? "Resume runs" : "Pause runs"}
          title="RunJobs"
          value={payload.settings.runs_paused ? "paused" : "running"}
          warning={payload.settings.runs_paused}
        />
      </section>

      <section className="grid gap-4 md:grid-cols-2">
        <ReaperPanel />
        <GithubCachePanel payload={payload} />
      </section>

      <ActionsTable actions={payload.recent_admin_actions} />
    </>
  )
}

function TogglePanel({
  title,
  description,
  value,
  label,
  command,
  warning
}: {
  title: string
  description: string
  value: string
  label: string
  command: ConsoleCommand
  warning: boolean
}) {
  const queryClient = useQueryClient()
  const mutation = useMutation({
    mutationFn: () => runConsoleCommand(command),
    onSuccess: (payload) => {
      queryClient.setQueryData(["admin", "console"], payload)
      void queryClient.invalidateQueries({ queryKey: ["admin", "overview"] })
    }
  })

  return (
    <section className="rounded border border-gray-200 bg-white p-4">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h2 className="font-medium text-gray-900">{title}</h2>
          <p className="mt-1 max-w-prose text-xs text-gray-600">{description}</p>
          <p className="mt-3 text-xs">
            State: <span className={`rounded px-2 py-0.5 font-mono uppercase ${warning ? "bg-amber-100 text-amber-700" : "bg-emerald-100 text-emerald-700"}`}>{value}</span>
          </p>
        </div>
        <button
          className={`rounded px-3 py-1.5 text-sm font-medium text-white disabled:cursor-not-allowed ${warning ? "bg-emerald-600 hover:bg-emerald-500 disabled:bg-emerald-300" : "bg-amber-600 hover:bg-amber-500 disabled:bg-amber-300"}`}
          disabled={mutation.isPending}
          onClick={() => mutation.mutate()}
          type="button"
        >
          {mutation.isPending ? "Saving..." : label}
        </button>
      </div>
    </section>
  )
}

function ReaperPanel() {
  const queryClient = useQueryClient()
  const mutation = useMutation({
    mutationFn: reapStaleRuns,
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["admin", "queue"] })
      void queryClient.invalidateQueries({ queryKey: ["admin", "overview"] })
      void queryClient.invalidateQueries({ queryKey: ["admin", "stuck"] })
    }
  })

  return (
    <section className="rounded border border-gray-200 bg-white p-4">
      <h2 className="font-medium text-gray-900">Reap stale Runs now</h2>
      <p className="mt-1 max-w-prose text-xs text-gray-600">Runs the stale-run reaper inline when the recurring reaper itself may be starved.</p>
      <button
        className="mt-4 rounded bg-red-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-red-500 disabled:cursor-not-allowed disabled:bg-red-300"
        disabled={mutation.isPending}
        onClick={() => mutation.mutate()}
        type="button"
      >
        {mutation.isPending ? "Running..." : "Reap now"}
      </button>
      {mutation.isError ? <p className="mt-2 text-xs text-red-700">Unable to run stale-run reaper.</p> : null}
    </section>
  )
}

function GithubCachePanel({ payload }: { payload: AdminConsolePayload }) {
  const queryClient = useQueryClient()
  const [userId, setUserId] = useState("")
  const mutation = useMutation({
    mutationFn: () => clearGithubCache(userId),
    onSuccess: (updated) => {
      queryClient.setQueryData(["admin", "console"], updated)
    }
  })

  return (
    <section className="rounded border border-gray-200 bg-white p-4">
      <h2 className="font-medium text-gray-900">GitHub HTTP cache</h2>
      <p className="mt-1 max-w-prose text-xs text-gray-600">Drops per-user GitHub ETag cache entries when conditional GET responses are stale.</p>
      <div className="mt-4 flex flex-col gap-2 sm:flex-row sm:items-center">
        <select
          className="rounded border border-gray-300 bg-white px-2 py-1.5 text-sm text-gray-700"
          onChange={(event) => setUserId(event.target.value)}
          value={userId}
        >
          <option value="">All users</option>
          {payload.users.map((user) => (
            <option key={user.id} value={user.id}>{user.email_address}</option>
          ))}
        </select>
        <button
          className="rounded bg-blue-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-blue-500 disabled:cursor-not-allowed disabled:bg-blue-300"
          disabled={mutation.isPending}
          onClick={() => mutation.mutate()}
          type="button"
        >
          {mutation.isPending ? "Clearing..." : "Clear cache"}
        </button>
      </div>
      {mutation.data?.message ? <p className="mt-2 text-xs text-emerald-700">{mutation.data.message}</p> : null}
      {mutation.isError ? <p className="mt-2 text-xs text-red-700">Unable to clear GitHub cache.</p> : null}
    </section>
  )
}

function ActionsTable({ actions }: { actions: ConsoleAction[] }) {
  return (
    <section className="rounded border border-gray-200 bg-white">
      <div className="border-b border-gray-200 bg-gray-50 px-4 py-2 text-xs font-medium uppercase text-gray-500">Recent admin actions</div>
      {actions.length === 0 ? (
        <PanelMessage>No admin actions logged yet.</PanelMessage>
      ) : (
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-gray-200 text-sm">
            <thead className="bg-gray-50 text-left text-xs font-medium uppercase text-gray-500">
              <tr>
                <th className="px-4 py-2">When</th>
                <th className="px-4 py-2">Operator</th>
                <th className="px-4 py-2">Action</th>
                <th className="px-4 py-2">Params</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {actions.map((action) => (
                <tr key={action.id}>
                  <td className="whitespace-nowrap px-4 py-2 text-xs text-gray-600">{formatDate(action.performed_at)}</td>
                  <td className="px-4 py-2 text-xs text-gray-700">{action.user_email}</td>
                  <td className="px-4 py-2 font-mono text-xs">{action.action}</td>
                  <td className="px-4 py-2 font-mono text-xs text-gray-500">{JSON.stringify(action.params).slice(0, 200)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  )
}

function ConsoleError({ error }: { error: Error }) {
  const message = error instanceof ApiError ? error.message : "Unable to load operator console."

  return <PanelMessage tone="error">{message}</PanelMessage>
}

function PanelMessage({ children, tone = "muted" }: { children: ReactNode; tone?: "muted" | "error" }) {
  return <div className={`p-4 text-sm ${tone === "error" ? "text-red-700" : "text-gray-600"}`}>{children}</div>
}

function formatDate(value: string) {
  return new Date(value).toLocaleString()
}
