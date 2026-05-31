import { useQuery } from "@tanstack/react-query"
import { Route, Routes } from "react-router-dom"
import { fetchBootstrap } from "../api/bootstrap"
import { useAppEvents } from "../lib/useAppEvents"
import { AdminConsole } from "./AdminConsole"
import { AdminInvitations } from "./AdminInvitations"
import { AdminInstallations } from "./AdminInstallations"
import { AdminOverview } from "./AdminOverview"
import { AdminQueueRoute } from "./AdminQueue"
import { AdminProcessDetail, AdminProcessesIndex } from "./AdminProcesses"
import { AdminSettings } from "./AdminSettings"
import { AdminStuck } from "./AdminStuck"
import { AdminTranscript } from "./AdminTranscript"
import { AdminUserDetailRoute, AdminUsersIndex } from "./AdminUsers"
import { ChatNewRoute } from "./ChatNew"
import { ChatRoute } from "./Chat"
import { CredentialsRoute } from "./Credentials"
import { CronTemplateDetailRoute, CronTemplateFormRoute, CronTemplatesIndex } from "./CronTemplates"
import { DirectJobNewRoute } from "./DirectJobNew"
import { EpicDetailRoute } from "./EpicDetail"
import { EpicFormRoute } from "./EpicForm"
import { RepositoriesIndex } from "./Repositories"
import { RepositoryDetailRoute } from "./RepositoryDetail"
import { RepositoryDocumentsRoute } from "./RepositoryDocuments"
import { RepositoryFormRoute } from "./RepositoryForm"
import { RepositoryScheduledTasksRoute } from "./RepositoryScheduledTasks"
import { ScheduledTaskDetailRoute, ScheduledTaskFormRoute, ScheduledTasksIndex } from "./ScheduledTasks"
import { SmartFolders } from "./SmartFolders"
import { Tags } from "./Tags"

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
      <Route path="/admin/users" element={<AdminUsersIndex />} />
      <Route path="/admin/users/:id" element={<AdminUserDetailRoute />} />
      <Route path="/admin/console" element={<AdminConsole />} />
      <Route path="/admin/installations" element={<AdminInstallations />} />
      <Route path="/invitations" element={<AdminInvitations />} />
      <Route path="/settings/edit" element={<AdminSettings />} />
      <Route path="/settings" element={<CredentialsRoute />} />
      <Route path="/credentials/edit" element={<CredentialsRoute />} />
      <Route path="/smart_folders" element={<SmartFolders />} />
      <Route path="/tags" element={<Tags />} />
      <Route path="/cron_templates" element={<CronTemplatesIndex />} />
      <Route path="/cron_templates/new" element={<CronTemplateFormRoute mode="new" />} />
      <Route path="/cron_templates/:id" element={<CronTemplateDetailRoute />} />
      <Route path="/cron_templates/:id/edit" element={<CronTemplateFormRoute mode="edit" />} />
      <Route path="/scheduled_tasks" element={<ScheduledTasksIndex />} />
      <Route path="/scheduled_tasks/:id" element={<ScheduledTaskDetailRoute />} />
      <Route path="/scheduled_tasks/:id/edit" element={<ScheduledTaskFormRoute mode="edit" />} />
      <Route path="/repositories/:repositoryId/scheduled_tasks" element={<RepositoryScheduledTasksRoute />} />
      <Route path="/repositories/:repositoryId/scheduled_tasks/new" element={<ScheduledTaskFormRoute mode="new" />} />
      <Route path="/repositories/:repositoryId/documents" element={<RepositoryDocumentsRoute />} />
      <Route path="/repositories/new" element={<RepositoryFormRoute mode="new" />} />
      <Route path="/repositories/:id/edit" element={<RepositoryFormRoute mode="edit" />} />
      <Route path="/repositories/:id" element={<RepositoryDetailRoute />} />
      <Route path="/repositories" element={<RepositoriesIndex />} />
      <Route path="/jobs/new" element={<DirectJobNewRoute />} />
      <Route path="/epics/new" element={<EpicFormRoute mode="new" />} />
      <Route path="/epics/:id/edit" element={<EpicFormRoute mode="edit" />} />
      <Route path="/epics/:id" element={<EpicDetailRoute />} />
      <Route path="/chats/new" element={<ChatNewRoute />} />
      <Route path="/chats/:id" element={<ChatRoute />} />
      <Route path="/app-shell/admin" element={<AdminOverview />} />
      <Route path="/app-shell/admin/queue" element={<AdminQueueRoute />} />
      <Route path="/app-shell/admin/queue/:tab" element={<AdminQueueRoute />} />
      <Route path="/app-shell/admin/stuck" element={<AdminStuck />} />
      <Route path="/app-shell/admin/processes" element={<AdminProcessesIndex />} />
      <Route path="/app-shell/admin/processes/:id" element={<AdminProcessDetail />} />
      <Route path="/app-shell/admin/runs/:runId/transcript" element={<AdminTranscript />} />
      <Route path="/app-shell/admin/users" element={<AdminUsersIndex />} />
      <Route path="/app-shell/admin/users/:id" element={<AdminUserDetailRoute />} />
      <Route path="/app-shell/admin/console" element={<AdminConsole />} />
      <Route path="/app-shell/admin/installations" element={<AdminInstallations />} />
      <Route path="/app-shell/invitations" element={<AdminInvitations />} />
      <Route path="/app-shell/settings/edit" element={<AdminSettings />} />
      <Route path="/app-shell/settings" element={<CredentialsRoute />} />
      <Route path="/app-shell/credentials/edit" element={<CredentialsRoute />} />
      <Route path="/app-shell/smart_folders" element={<SmartFolders />} />
      <Route path="/app-shell/tags" element={<Tags />} />
      <Route path="/app-shell/cron_templates" element={<CronTemplatesIndex />} />
      <Route path="/app-shell/cron_templates/new" element={<CronTemplateFormRoute mode="new" />} />
      <Route path="/app-shell/cron_templates/:id" element={<CronTemplateDetailRoute />} />
      <Route path="/app-shell/cron_templates/:id/edit" element={<CronTemplateFormRoute mode="edit" />} />
      <Route path="/app-shell/scheduled_tasks" element={<ScheduledTasksIndex />} />
      <Route path="/app-shell/scheduled_tasks/:id" element={<ScheduledTaskDetailRoute />} />
      <Route path="/app-shell/scheduled_tasks/:id/edit" element={<ScheduledTaskFormRoute mode="edit" />} />
      <Route path="/app-shell/repositories/:repositoryId/scheduled_tasks" element={<RepositoryScheduledTasksRoute />} />
      <Route path="/app-shell/repositories/:repositoryId/scheduled_tasks/new" element={<ScheduledTaskFormRoute mode="new" />} />
      <Route path="/app-shell/repositories/:repositoryId/documents" element={<RepositoryDocumentsRoute />} />
      <Route path="/app-shell/repositories/new" element={<RepositoryFormRoute mode="new" />} />
      <Route path="/app-shell/repositories/:id/edit" element={<RepositoryFormRoute mode="edit" />} />
      <Route path="/app-shell/repositories/:id" element={<RepositoryDetailRoute />} />
      <Route path="/app-shell/repositories" element={<RepositoriesIndex />} />
      <Route path="/app-shell/jobs/new" element={<DirectJobNewRoute />} />
      <Route path="/app-shell/epics/new" element={<EpicFormRoute mode="new" />} />
      <Route path="/app-shell/epics/:id/edit" element={<EpicFormRoute mode="edit" />} />
      <Route path="/app-shell/epics/:id" element={<EpicDetailRoute />} />
      <Route path="/app-shell/chats/new" element={<ChatNewRoute />} />
      <Route path="/app-shell/chats/:id" element={<ChatRoute />} />
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
