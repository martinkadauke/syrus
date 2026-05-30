import { useQuery } from "@tanstack/react-query"
import { Route, Routes } from "react-router-dom"
import { fetchBootstrap } from "../api/bootstrap"
import { useAppEvents } from "../lib/useAppEvents"
import { AdminOverview } from "./AdminOverview"
import { AdminQueueRoute } from "./AdminQueue"
import { AdminProcessDetail, AdminProcessesIndex } from "./AdminProcesses"
import { AdminStuck } from "./AdminStuck"
import { AdminTranscript } from "./AdminTranscript"

export function App() {
  useAppEvents()

  return (
    <Routes>
      <Route path="/admin" element={<AdminOverview />} />
      <Route path="/admin/queue" element={<AdminQueueRoute />} />
      <Route path="/admin/queue/:tab" element={<AdminQueueRoute />} />
      <Route path="/admin/stuck" element={<AdminStuck />} />
      <Route path="/admin/processes" element={<AdminProcessesIndex />} />
      <Route path="/admin/processes/:id" element={<AdminProcessDetail />} />
      <Route path="/admin/runs/:runId/transcript" element={<AdminTranscript />} />
      <Route path="/app-shell/admin" element={<AdminOverview />} />
      <Route path="/app-shell/admin/queue" element={<AdminQueueRoute />} />
      <Route path="/app-shell/admin/queue/:tab" element={<AdminQueueRoute />} />
      <Route path="/app-shell/admin/stuck" element={<AdminStuck />} />
      <Route path="/app-shell/admin/processes" element={<AdminProcessesIndex />} />
      <Route path="/app-shell/admin/processes/:id" element={<AdminProcessDetail />} />
      <Route path="/app-shell/admin/runs/:runId/transcript" element={<AdminTranscript />} />
      <Route path="*" element={<BootstrapShell />} />
    </Routes>
  )
}

function BootstrapShell() {
  const bootstrap = useQuery({
    queryKey: ["bootstrap"],
    queryFn: fetchBootstrap
  })

  if (bootstrap.isPending) {
    return <main aria-label="Syrus SPA" className="p-6 text-sm text-gray-600">Loading...</main>
  }

  if (bootstrap.isError) {
    return (
      <main aria-label="Syrus SPA" className="p-6">
        <p className="text-sm text-red-700">Unable to load the app shell.</p>
      </main>
    )
  }

  const { current_user: user, app } = bootstrap.data

  return (
    <main aria-label="Syrus SPA" className="mx-auto max-w-5xl space-y-6 p-6">
      <header className="border-b border-gray-200 pb-4">
        <p className="text-xs font-medium uppercase text-gray-500">React shell</p>
        <h1 className="mt-1 text-2xl font-semibold text-gray-900">Syrus</h1>
      </header>

      <section className="grid gap-4 sm:grid-cols-2">
        <div className="rounded border border-gray-200 bg-white p-4">
          <h2 className="text-sm font-medium text-gray-900">Signed in</h2>
          <p className="mt-2 text-sm text-gray-700">{user.display_name}</p>
          <p className="text-xs text-gray-500">{user.email_address}</p>
        </div>

        <div className="rounded border border-gray-200 bg-white p-4">
          <h2 className="text-sm font-medium text-gray-900">Revision</h2>
          <p className="mt-2 font-mono text-sm text-gray-700">{app.revision}</p>
          {app.revision_url ? (
            <a className="text-xs text-blue-600 underline hover:no-underline" href={app.revision_url}>
              View commit
            </a>
          ) : null}
        </div>
      </section>
    </main>
  )
}
