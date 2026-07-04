import { useEffect, useState } from "react"
import { useQuery, useQueryClient } from "@tanstack/react-query"
import { fetchAdminGithubAppConfirm, fetchAdminGithubAppRegister, syncAdminGithubAppInstallations } from "../api/adminGithubApp"
import { ApiError } from "../api/client"
import { openInNewTab } from "../lib/desktopShell"

// Admin-only panel: create the singleton Syrus GitHub App from a manifest,
// then install it on the operator's account (All repositories recommended —
// repos added to Syrus later connect automatically). Registering the App
// satisfies the GitHub onboarding step; installation is encouraged here but
// skippable, with a per-repository fallback offer at add-repository time.
export function GithubAppPanel({ onClose, onSaved }: { onClose: () => void; onSaved?: () => void }) {
  const queryClient = useQueryClient()
  const [awaiting, setAwaiting] = useState(false)
  const [awaitingInstall, setAwaitingInstall] = useState(false)
  const [popupBlocked, setPopupBlocked] = useState<string | null>(null)

  // Fetched once: generates the manifest + the session state GitHub echoes
  // back to the callback. Refetching would rotate that state, so keep it stable.
  const register = useQuery({
    queryKey: ["admin", "github_app", "register", "onboarding"],
    queryFn: () => fetchAdminGithubAppRegister("onboarding"),
    staleTime: Number.POSITIVE_INFINITY,
    refetchOnWindowFocus: false
  })

  // Polled while we wait for GitHub — first for the registration callback,
  // then for the installation to be discovered.
  const confirm = useQuery({
    queryKey: ["admin", "github_app", "confirm"],
    queryFn: fetchAdminGithubAppConfirm,
    refetchInterval: awaiting || awaitingInstall ? 3000 : false,
    refetchOnWindowFocus: true
  })

  const status = confirm.data?.github_app ?? register.data?.github_app
  const registered = !!status?.registered
  const installations = status?.installations ?? []
  const installed = installations.length > 0

  // Once the App is registered, the GitHub step is satisfied — refresh
  // bootstrap so the checklist marks it complete, and stop polling.
  useEffect(() => {
    if (!registered) return
    setAwaiting(false)
    void queryClient.invalidateQueries({ queryKey: ["bootstrap"] })
    onSaved?.()
  }, [registered])

  // Installations are only discovered by polling GitHub (Syrus has no
  // webhooks) — while the operator is on GitHub's install page, keep asking
  // the server to sync so detection takes seconds, not the 5-minute
  // recurring sweep. The endpoint throttles enqueues server-side.
  useEffect(() => {
    if (!awaitingInstall || installed) return
    syncAdminGithubAppInstallations().catch(() => {})
  }, [awaitingInstall, installed, confirm.dataUpdatedAt])

  useEffect(() => {
    if (installed) setAwaitingInstall(false)
  }, [installed])

  if (register.isPending) {
    return <p className="text-sm text-gray-500 dark:text-gray-400">Loading GitHub App registration…</p>
  }

  if (register.isError) {
    const forbidden = register.error instanceof ApiError && register.error.status === 403
    return (
      <Box tone="muted">
        {forbidden
          ? "Only an admin can register the Syrus GitHub App. Ask an admin to set it up, or use a personal access token instead."
          : "Could not load GitHub App registration. Use a personal access token instead."}
      </Box>
    )
  }

  if (registered && installed) {
    return (
      <div className="space-y-4">
        <Box tone="ok">
          Installed on {installations.map((i) => i.account_login).join(", ")} — Syrus acts through its own bot identity there, and repositories you add connect automatically.
        </Box>
        <div className="flex justify-end">
          <button className="rounded-md bg-blue-600 px-3 py-2 text-sm font-medium text-white hover:bg-blue-700" onClick={onClose} type="button">
            Done
          </button>
        </div>
      </div>
    )
  }

  if (registered) {
    return (
      <div className="space-y-4">
        <Box tone="ok">The Syrus GitHub App is registered.</Box>
        <p className="text-sm text-gray-600 dark:text-gray-400">
          One more step: install it on your GitHub account so Syrus acts through its own bot identity. We recommend
          keeping GitHub&apos;s <span className="font-medium text-gray-900 dark:text-gray-100">All repositories</span> default —
          repositories you add to Syrus then connect automatically. Skip it and Syrus works through your personal
          access token, with a per-repository offer when you add one.
        </p>

        {status?.install_url ? (
          <button
            className="inline-flex items-center gap-1 rounded bg-blue-600 px-3 py-2 text-sm font-medium text-white hover:bg-blue-700"
            type="button"
            onClick={() => {
              const installUrl = status.install_url as string
              setPopupBlocked(openInNewTab(installUrl) ? null : installUrl)
              setAwaitingInstall(true)
              syncAdminGithubAppInstallations().catch(() => {})
            }}
          >
            Install on GitHub <span aria-hidden="true">↗</span>
          </button>
        ) : null}

        {popupBlocked ? (
          <p className="text-xs text-amber-700 dark:text-amber-300">
            Popup blocked.{" "}
            <a className="font-medium underline" href={popupBlocked} rel="noreferrer" target="_blank">
              Open the install page
            </a>{" "}
            manually.
          </p>
        ) : null}

        {awaitingInstall ? (
          <p className="flex items-center gap-2 text-sm text-gray-500 dark:text-gray-400" role="status">
            <Spinner /> Waiting for GitHub — this updates by itself once the App is installed…
          </p>
        ) : null}

        <div className="flex justify-end">
          <button className="rounded-md border border-gray-300 dark:border-gray-600 px-3 py-2 text-sm text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-800" onClick={onClose} type="button">
            {awaitingInstall ? "Close — it keeps connecting in the background" : "Skip for now"}
          </button>
        </div>
      </div>
    )
  }

  return (
    <div className="space-y-4 text-sm text-gray-700 dark:text-gray-300">
      <p className="text-gray-600 dark:text-gray-400">
        The GitHub App enables actions to appear as a bot natively on your repositories.
      </p>
      <ol className="space-y-2">
        <li><span className="font-medium text-gray-900 dark:text-gray-100">1.</span> Create the App on GitHub (opens in your browser).</li>
        <li><span className="font-medium text-gray-900 dark:text-gray-100">2.</span> GitHub sends you back — Syrus picks it up automatically.</li>
      </ol>

      <button
        className="inline-flex items-center gap-1 rounded bg-blue-600 px-3 py-2 text-sm font-medium text-white hover:bg-blue-700"
        type="button"
        onClick={() => {
          const bounceUrl = register.data.bounce_url
          setPopupBlocked(openInNewTab(bounceUrl) ? null : bounceUrl)
          setAwaiting(true)
        }}
      >
        {register.data.submit_label} <span aria-hidden="true">↗</span>
      </button>

      {popupBlocked ? (
        <p className="text-xs text-amber-700 dark:text-amber-300">
          Popup blocked.{" "}
          <a className="font-medium underline" href={popupBlocked} rel="noreferrer" target="_blank">
            Open the registration page
          </a>{" "}
          manually.
        </p>
      ) : null}

      {awaiting ? (
        <p className="flex items-center gap-2 text-sm text-gray-500 dark:text-gray-400" role="status">
          <Spinner /> Waiting for GitHub to finish creating the App…
        </p>
      ) : null}
    </div>
  )
}

function Box({ tone, children }: { tone: "ok" | "muted"; children: React.ReactNode }) {
  const toneClass = tone === "ok"
    ? "border-green-200 bg-green-50 text-green-800 dark:border-green-900 dark:bg-green-950/40 dark:text-green-300"
    : "border-gray-200 bg-gray-50 text-gray-600 dark:border-gray-700 dark:bg-gray-800/50 dark:text-gray-400"
  return <p className={`rounded border px-3 py-2 text-sm ${toneClass}`} role={tone === "ok" ? "status" : undefined}>{children}</p>
}

function Spinner() {
  return (
    <svg aria-hidden="true" className="h-4 w-4 animate-spin text-gray-400" fill="none" viewBox="0 0 24 24">
      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
      <path className="opacity-75" d="M4 12a8 8 0 018-8" fill="currentColor" />
    </svg>
  )
}
