import { useQuery } from "@tanstack/react-query"
import type { ReactNode } from "react"
import { Link, Route, Routes, useLocation } from "react-router-dom"
import { fetchBootstrap, readInitialBootstrap, type BootstrapPayload } from "../api/bootstrap"
import { BugReportButton } from "../components/BugReportButton"
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
import { DashboardRoute } from "./Dashboard"
import { DirectJobNewRoute } from "./DirectJobNew"
import { EpicDetailRoute } from "./EpicDetail"
import { EpicFormRoute } from "./EpicForm"
import { JobDetailRoute } from "./JobDetail"
import { RepositoriesIndex } from "./Repositories"
import { RepositoryDetailRoute } from "./RepositoryDetail"
import { RepositoryDocumentsRoute } from "./RepositoryDocuments"
import { RepositoryFormRoute } from "./RepositoryForm"
import { RepositoryScheduledTasksRoute } from "./RepositoryScheduledTasks"
import { ScheduledTaskDetailRoute, ScheduledTaskFormRoute, ScheduledTasksIndex } from "./ScheduledTasks"
import { SmartFolders } from "./SmartFolders"
import { Tags } from "./Tags"

type AppRouteDefinition = {
  path: string
  element: ReactNode
}

const appRouteDefinitions: AppRouteDefinition[] = [
  { path: "/dashboard", element: <DashboardRoute /> },
  { path: "/dashboard/epics", element: <DashboardRoute /> },
  { path: "/dashboard/jobs", element: <DashboardRoute /> },
  { path: "/dashboard/workflows", element: <DashboardRoute /> },
  { path: "/admin", element: <AdminOverview /> },
  { path: "/admin/queue", element: <AdminQueueRoute /> },
  { path: "/admin/queue/:tab", element: <AdminQueueRoute /> },
  { path: "/admin/stuck", element: <AdminStuck /> },
  { path: "/admin/processes", element: <AdminProcessesIndex /> },
  { path: "/admin/processes/:id", element: <AdminProcessDetail /> },
  { path: "/admin/runs/:runId/transcript", element: <AdminTranscript /> },
  { path: "/admin/users", element: <AdminUsersIndex /> },
  { path: "/admin/users/:id", element: <AdminUserDetailRoute /> },
  { path: "/admin/console", element: <AdminConsole /> },
  { path: "/admin/installations", element: <AdminInstallations /> },
  { path: "/invitations", element: <AdminInvitations /> },
  { path: "/settings/edit", element: <AdminSettings /> },
  { path: "/settings", element: <CredentialsRoute /> },
  { path: "/credentials/edit", element: <CredentialsRoute /> },
  { path: "/smart_folders", element: <SmartFolders /> },
  { path: "/tags", element: <Tags /> },
  { path: "/cron_templates", element: <CronTemplatesIndex /> },
  { path: "/cron_templates/new", element: <CronTemplateFormRoute mode="new" /> },
  { path: "/cron_templates/:id", element: <CronTemplateDetailRoute /> },
  { path: "/cron_templates/:id/edit", element: <CronTemplateFormRoute mode="edit" /> },
  { path: "/scheduled_tasks", element: <ScheduledTasksIndex /> },
  { path: "/scheduled_tasks/:id", element: <ScheduledTaskDetailRoute /> },
  { path: "/scheduled_tasks/:id/edit", element: <ScheduledTaskFormRoute mode="edit" /> },
  { path: "/repositories/:repositoryId/scheduled_tasks", element: <RepositoryScheduledTasksRoute /> },
  { path: "/repositories/:repositoryId/scheduled_tasks/new", element: <ScheduledTaskFormRoute mode="new" /> },
  { path: "/repositories/:repositoryId/documents", element: <RepositoryDocumentsRoute /> },
  { path: "/repositories/new", element: <RepositoryFormRoute mode="new" /> },
  { path: "/repositories/:id/edit", element: <RepositoryFormRoute mode="edit" /> },
  { path: "/repositories/:id", element: <RepositoryDetailRoute /> },
  { path: "/repositories", element: <RepositoriesIndex /> },
  { path: "/jobs/new", element: <DirectJobNewRoute /> },
  { path: "/jobs/:id/source", element: <JobDetailRoute /> },
  { path: "/jobs/:id", element: <JobDetailRoute /> },
  { path: "/epics/new", element: <EpicFormRoute mode="new" /> },
  { path: "/epics/:id/edit", element: <EpicFormRoute mode="edit" /> },
  { path: "/epics/:id", element: <EpicDetailRoute /> },
  { path: "/chats/new", element: <ChatNewRoute /> },
  { path: "/chats/:id", element: <ChatRoute /> }
]

export function App() {
  useAppEvents()
  const initialBootstrap = readInitialBootstrap()

  return (
    <AppChrome initialBootstrap={initialBootstrap}>
      <Routes>
        <Route path="/" element={<DashboardRoute />} />
        {renderAppRoutes()}
        <Route path="*" element={<BootstrapShell initialBootstrap={initialBootstrap} />} />
      </Routes>
    </AppChrome>
  )
}

function renderAppRoutes() {
  return appRouteDefinitions.flatMap(({ path, element }) => [
    <Route element={element} key={path} path={path} />,
    <Route element={element} key={`/app-shell${path}`} path={`/app-shell${path}`} />
  ])
}

function AppChrome({ children, initialBootstrap }: { children: ReactNode; initialBootstrap: BootstrapPayload | null }) {
  const location = useLocation()
  const prefix = location.pathname.startsWith("/app-shell") ? "/app-shell" : ""
  const bootstrap = useQuery({
    queryKey: ["bootstrap"],
    queryFn: fetchBootstrap,
    enabled: initialBootstrap != null,
    initialData: initialBootstrap ?? undefined,
    staleTime: Number.POSITIVE_INFINITY
  })
  const data = initialBootstrap ? bootstrap.data ?? initialBootstrap : null
  const user = data?.current_user
  const app = data?.app
  const defaultChatPath = withRoutePrefix(data?.navigation?.default_chat_path || "/chats/new", prefix)
  const navItems: Array<{ label: string; to: string; active: boolean; desktopOnly?: boolean }> = [
    { label: "Dashboard", to: `${prefix}/dashboard/jobs?view=list`, active: location.pathname === "/" || location.pathname.includes("/dashboard") },
    { label: "Repos", to: `${prefix}/repositories`, active: location.pathname.includes("/repositories") },
    { label: "Schedules", to: `${prefix}/scheduled_tasks`, active: location.pathname.includes("/scheduled_tasks"), desktopOnly: true }
  ]

  return (
    <div className="min-h-screen bg-gray-50 text-gray-900">
      <header className="border-b border-gray-200 bg-white">
        <div className="mx-auto flex max-w-7xl flex-wrap items-center justify-between gap-3 px-6 py-3">
          <div className="flex min-w-0 items-center gap-5">
            <Link className="text-lg font-semibold text-gray-900" to={defaultChatPath}>Syrus</Link>
            <nav aria-label="Primary" className="flex flex-wrap gap-1 text-sm">
              {navItems.map((item) => (
                <Link className={`${item.desktopOnly ? "hidden sm:inline-flex" : ""} ${navLinkClass(item.active)}`} key={item.label} to={item.to}>{item.label}</Link>
              ))}
            </nav>
          </div>
          <div className="flex flex-wrap items-center justify-end gap-2 text-xs text-gray-500">
            {user ? (
              <nav aria-label="Account" className="flex items-center gap-2">
                {user.admin ? <Link className={accountLinkClass()} to={`${prefix}/admin`}>Admin</Link> : null}
                <Link className={accountLinkClass()} to={`${prefix}/settings`}>Settings</Link>
              </nav>
            ) : null}
            {user ? <span className="hidden sm:inline">{user.display_name}</span> : null}
            {app ? <span className="hidden font-mono sm:inline">{app.revision}</span> : null}
            <form action="/session" method="post">
              {data?.csrf_token ? <input name="authenticity_token" type="hidden" value={data.csrf_token} /> : null}
              <input name="_method" type="hidden" value="delete" />
              <button className="rounded border border-gray-200 bg-white px-2.5 py-1 text-gray-600 hover:border-gray-300 hover:text-gray-900" type="submit">Sign out</button>
            </form>
          </div>
        </div>
      </header>
      {children}
      {user ? <BugReportButton context={bugReportContext(location.pathname)} /> : null}
    </div>
  )
}

function bugReportContext(pathname: string) {
  const normalized = pathname.replace(/^\/app-shell/, "") || "/"
  if (normalized === "/" || normalized === "/dashboard") return "Dashboard"

  const label = normalized
    .split("/")
    .filter(Boolean)
    .filter((segment) => !/^\d+$/.test(segment))
    .map((segment) => segment.replace(/_/g, " "))
    .join(" ")

  return label ? titleize(label) : "Syrus"
}

function titleize(value: string) {
  return value.replace(/\b\w/g, (letter) => letter.toUpperCase())
}

function BootstrapShell({ initialBootstrap }: { initialBootstrap: BootstrapPayload | null }) {
  const bootstrap = useQuery({
    queryKey: ["bootstrap"],
    queryFn: fetchBootstrap,
    initialData: initialBootstrap ?? undefined,
    staleTime: initialBootstrap ? Number.POSITIVE_INFINITY : 0
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

function navLinkClass(active: boolean) {
  return `rounded px-2.5 py-1.5 font-medium ${active ? "bg-blue-50 text-blue-700" : "text-gray-700 hover:bg-gray-100"}`
}

function accountLinkClass() {
  return "rounded border border-gray-200 bg-white px-2.5 py-1 font-medium text-gray-700 hover:border-gray-300 hover:text-gray-900"
}

function withRoutePrefix(path: string, prefix: string) {
  if (!prefix || path.startsWith(prefix)) return path
  return `${prefix}${path.startsWith("/") ? path : `/${path}`}`
}
