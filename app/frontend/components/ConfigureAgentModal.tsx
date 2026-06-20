import { useEffect, useRef, useState } from "react"
import { useQueryClient } from "@tanstack/react-query"
import { fetchCredentials, startClaudeOauth, testClaudeCli, type CredentialTestResult } from "../api/credentials"
import { CloseIcon } from "./CloseIcon"

type AgentTab = "claude" | "codex"

type Preflight =
  | { status: "checking" }
  | { status: "done"; result: CredentialTestResult }
  | { status: "error" }

type OauthPhase =
  | { status: "idle" }
  | { status: "authorizing" }
  | { status: "connected"; message: string }
  | { status: "error"; message: string }

const OAUTH_MESSAGE_TYPE = "syrus:claude-oauth"
const POLL_INTERVAL_MS = 2500

export function ConfigureAgentModal({ onClose, onSaved }: { onClose: () => void; onSaved?: () => void }) {
  const queryClient = useQueryClient()
  const [tab, setTab] = useState<AgentTab>("claude")
  const [preflight, setPreflight] = useState<Preflight>({ status: "checking" })
  const [oauth, setOauth] = useState<OauthPhase>({ status: "idle" })
  const [popupBlocked, setPopupBlocked] = useState<string | null>(null)

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") onClose()
    }
    document.addEventListener("keydown", onKeyDown)
    return () => document.removeEventListener("keydown", onKeyDown)
  }, [onClose])

  // Preflight: is Claude already usable on this machine?
  useEffect(() => {
    let cancelled = false
    testClaudeCli()
      .then((payload) => {
        if (!cancelled) setPreflight({ status: "done", result: payload.credential_test })
      })
      .catch(() => {
        if (!cancelled) setPreflight({ status: "error" })
      })
    return () => {
      cancelled = true
    }
  }, [])

  async function onConnected(message: string) {
    await queryClient.invalidateQueries({ queryKey: ["bootstrap"] })
    await queryClient.invalidateQueries({ queryKey: ["credentials"] })
    setOauth({ status: "connected", message })
    onSaved?.()
  }

  // While authorizing, listen for the callback window's postMessage and also
  // poll credential status as a fallback (in case the message is blocked).
  useEffect(() => {
    if (oauth.status !== "authorizing") return

    function onMessage(event: MessageEvent) {
      if (event.origin !== window.location.origin) return
      if (event.data?.type !== OAUTH_MESSAGE_TYPE) return
      if (event.data.ok) {
        void onConnected(event.data.message || "Claude connected.")
      } else {
        setOauth({ status: "error", message: event.data.message || "Authorization failed. Try again." })
      }
    }

    window.addEventListener("message", onMessage)
    const poll = window.setInterval(async () => {
      try {
        const creds = await fetchCredentials()
        if (creds.credential_status.claude_oauth_token) {
          void onConnected("Claude connected.")
        }
      } catch {
        // keep polling
      }
    }, POLL_INTERVAL_MS)

    return () => {
      window.removeEventListener("message", onMessage)
      window.clearInterval(poll)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [oauth.status])

  async function authorize() {
    setPopupBlocked(null)
    setOauth({ status: "authorizing" })
    try {
      const { authorize_url } = await startClaudeOauth()
      const popup = window.open(authorize_url, "syrus-claude-oauth", "width=560,height=820")
      if (!popup) setPopupBlocked(authorize_url)
    } catch (err) {
      setOauth({ status: "error", message: err instanceof Error ? err.message : "Could not start authorization." })
    }
  }

  const ambientReady = preflight.status === "done" && preflight.result.ok

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" onClick={onClose}>
      <section
        aria-labelledby="configure-agent-title"
        aria-modal="true"
        className="max-h-[calc(100vh-2rem)] w-full max-w-lg overflow-y-auto rounded-lg bg-white dark:bg-gray-900 shadow-xl"
        role="dialog"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="space-y-5 p-5 sm:p-6">
          <div className="flex items-start justify-between gap-4">
            <div>
              <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100" id="configure-agent-title">
                Configure agent
              </h2>
              <p className="mt-1 text-sm text-gray-600 dark:text-gray-400">
                Set the default agent Syrus uses for runs. You can add more or switch later in My credentials.
              </p>
            </div>
            <button
              aria-label="Close"
              className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg text-gray-500 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800 hover:text-gray-700 dark:hover:text-gray-300 focus:outline-none focus:ring-2 focus:ring-blue-500"
              onClick={onClose}
              type="button"
            >
              <CloseIcon className="h-7 w-7" />
            </button>
          </div>

          {/* Provider tabs. Codex lands in a follow-up step. */}
          <div className="flex border-b border-gray-200 dark:border-gray-700" role="tablist">
            <button
              aria-selected={tab === "claude"}
              className={tabClass(tab === "claude")}
              onClick={() => setTab("claude")}
              role="tab"
              type="button"
            >
              Claude
            </button>
            <button
              aria-disabled="true"
              aria-selected={false}
              className="cursor-not-allowed px-4 py-2 text-sm font-medium text-gray-400 dark:text-gray-600"
              disabled
              role="tab"
              title="Codex support is coming next"
              type="button"
            >
              Codex
              <span className="ml-2 rounded bg-gray-100 px-1.5 py-0.5 text-[10px] font-semibold uppercase text-gray-400 dark:bg-gray-800 dark:text-gray-500">Soon</span>
            </button>
          </div>

          {oauth.status === "connected" ? (
            <StatusBox tone="ok">{oauth.message}</StatusBox>
          ) : (
            <div className="space-y-4">
              {preflight.status === "checking" ? (
                <p className="flex items-center gap-2 text-sm text-gray-500 dark:text-gray-400" role="status">
                  <Spinner /> Checking for an existing Claude login on this machine…
                </p>
              ) : null}

              {ambientReady ? (
                <StatusBox tone="ok">
                  Claude already works on this machine. You can connect a durable token below (recommended for restarts and headless workers), or skip for now.
                </StatusBox>
              ) : null}

              <p className="text-sm text-gray-600 dark:text-gray-400">
                Authorizing opens <span className="font-medium">claude.ai</span> in a new window. Approve access and
                Syrus captures the token automatically — no terminal, no copy-paste. Requires a Claude Pro, Max, Team,
                or Enterprise plan.
              </p>

              {oauth.status === "error" ? <StatusBox tone="error">{oauth.message}</StatusBox> : null}

              {popupBlocked ? (
                <StatusBox tone="warning">
                  Your browser blocked the popup.{" "}
                  <a className="font-medium underline" href={popupBlocked} rel="noreferrer" target="_blank">
                    Open the authorization page
                  </a>{" "}
                  manually.
                </StatusBox>
              ) : null}

              <div className="flex items-center justify-end gap-2">
                <button
                  className="rounded-md border border-gray-300 dark:border-gray-600 px-3 py-2 text-sm text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-800"
                  onClick={onClose}
                  type="button"
                >
                  {ambientReady ? "Skip for now" : "Cancel"}
                </button>
                <button
                  className="inline-flex items-center gap-2 rounded-md bg-blue-600 px-3 py-2 text-sm font-medium text-white hover:bg-blue-700 disabled:opacity-60"
                  disabled={oauth.status === "authorizing"}
                  onClick={authorize}
                  type="button"
                >
                  {oauth.status === "authorizing" ? (
                    <>
                      <Spinner light /> Waiting for approval…
                    </>
                  ) : (
                    "Authorize with Claude"
                  )}
                </button>
              </div>
            </div>
          )}

          {oauth.status === "connected" ? (
            <div className="flex justify-end">
              <button
                className="rounded-md bg-blue-600 px-3 py-2 text-sm font-medium text-white hover:bg-blue-700"
                onClick={onClose}
                type="button"
              >
                Done
              </button>
            </div>
          ) : null}
        </div>
      </section>
    </div>
  )
}

function tabClass(active: boolean) {
  const base = "px-4 py-2 text-sm font-medium -mb-px border-b-2"
  return active
    ? `${base} border-blue-600 text-blue-700 dark:text-blue-300`
    : `${base} border-transparent text-gray-500 dark:text-gray-400`
}

function StatusBox({ tone, children }: { tone: "ok" | "warning" | "error"; children: React.ReactNode }) {
  const toneClass =
    tone === "ok"
      ? "border-green-200 bg-green-50 text-green-800 dark:border-green-900 dark:bg-green-950/40 dark:text-green-300"
      : tone === "warning"
        ? "border-amber-200 bg-amber-50 text-amber-800 dark:border-amber-900 dark:bg-amber-950/40 dark:text-amber-300"
        : "border-red-200 bg-red-50 text-red-700 dark:border-red-900 dark:bg-red-950/40 dark:text-red-300"
  return (
    <p className={`rounded border px-3 py-2 text-sm ${toneClass}`} role={tone === "ok" ? "status" : "alert"}>
      {children}
    </p>
  )
}

function Spinner({ light }: { light?: boolean }) {
  return (
    <svg aria-hidden="true" className={`h-4 w-4 animate-spin ${light ? "text-white" : "text-gray-400"}`} fill="none" viewBox="0 0 24 24">
      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
      <path className="opacity-75" d="M4 12a8 8 0 018-8" fill="currentColor" />
    </svg>
  )
}
