import { useEffect, useRef, useState } from "react"
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"
import { useT } from "../../hooks/useT"
import { fetchJobPreview, startJobPreview, stopJobPreview, type PreviewEnvironmentRecord } from "../../api/jobs"
import { errorMessage } from "../../lib/errorMessage"
import type { JobDetailQueryKey } from "./queryKeys"

const ACTIVE_STATES = ["starting", "seeding", "running", "stopping"] as const
const POLL_INTERVAL_MS = 3000

function isActive(state: PreviewEnvironmentRecord["state"]) {
  return (ACTIVE_STATES as readonly string[]).includes(state)
}

function useCountdown(expiresAt: string | null) {
  const [remaining, setRemaining] = useState<string | null>(null)

  useEffect(() => {
    if (!expiresAt) { setRemaining(null); return }

    function update() {
      const ms = new Date(expiresAt!).getTime() - Date.now()
      if (ms <= 0) { setRemaining(null); return }
      const totalSeconds = Math.floor(ms / 1000)
      const minutes = Math.floor(totalSeconds / 60)
      const seconds = totalSeconds % 60
      setRemaining(`${minutes}m ${String(seconds).padStart(2, "0")}s`)
    }

    update()
    const id = window.setInterval(update, 1000)
    return () => window.clearInterval(id)
  }, [expiresAt])

  return remaining
}

export function PreviewPanel({
  jobId,
  previewPath,
  canStart,
  initialPreview,
  queryKey
}: {
  jobId: number
  previewPath: string
  canStart: boolean
  initialPreview: PreviewEnvironmentRecord | null
  queryKey: JobDetailQueryKey
}) {
  const { t } = useT("jobs")
  const queryClient = useQueryClient()
  const [error, setError] = useState<string | null>(null)

  const preview = useQuery({
    queryKey: ["job-preview", jobId],
    queryFn: () => fetchJobPreview(previewPath),
    select: (data) => data.preview,
    initialData: { preview: initialPreview },
    refetchInterval: (query) => {
      const env = query.state.data?.preview
      return env && isActive(env.state) ? POLL_INTERVAL_MS : false
    }
  })

  const env = preview.data

  const start = useMutation({
    mutationFn: () => startJobPreview(previewPath),
    onSuccess: (data) => {
      queryClient.setQueryData(["job-preview", jobId], { preview: data.preview })
      void queryClient.invalidateQueries({ queryKey })
      setError(null)
    },
    onError: (err) => setError(errorMessage(err, t("preview_failed")))
  })

  const stop = useMutation({
    mutationFn: () => stopJobPreview(previewPath),
    onSuccess: (data) => {
      queryClient.setQueryData(["job-preview", jobId], { preview: data.preview })
      void queryClient.invalidateQueries({ queryKey })
      setError(null)
    },
    onError: (err) => setError(errorMessage(err, t("preview_failed")))
  })

  const countdown = useCountdown(env?.state === "running" ? env.expires_at : null)
  const expired = env?.state === "running" && env.expires_at != null && new Date(env.expires_at) <= new Date()

  if (!canStart && !env) return null

  const isPending = start.isPending || stop.isPending

  return (
    <section className="rounded border border-gray-200 bg-white p-4 text-sm dark:border-gray-700 dark:bg-gray-900" aria-label={t("preview_section")}>
      <h2 className="font-semibold text-gray-900 dark:text-gray-100">{t("preview_section")}</h2>
      <div className="mt-3 space-y-2">
        {error ? <p className="text-xs text-red-600 dark:text-red-400" role="alert">{error}</p> : null}
        <PreviewControls
          env={env ?? null}
          canStart={canStart}
          expired={expired}
          isPending={isPending}
          onStart={() => start.mutate()}
          onStop={() => stop.mutate()}
          t={t}
        />
        {env?.state === "running" && !expired && countdown ? (
          <p className="text-xs text-gray-500 dark:text-gray-400">{t("preview_expires_in", { time: countdown })}</p>
        ) : null}
        {expired ? (
          <p className="text-xs text-amber-600 dark:text-amber-400">{t("preview_expired")}</p>
        ) : null}
        {env?.state === "failed" && env.error_message ? (
          <p className="text-xs text-red-600 dark:text-red-400" role="alert">{env.error_message}</p>
        ) : null}
      </div>
    </section>
  )
}

function PreviewControls({
  env,
  canStart,
  expired,
  isPending,
  onStart,
  onStop,
  t
}: {
  env: PreviewEnvironmentRecord | null
  canStart: boolean
  expired: boolean
  isPending: boolean
  onStart: () => void
  onStop: () => void
  t: ReturnType<typeof useT>["t"]
}) {
  const state = env?.state

  if (!state || state === "stopped" || state === "failed") {
    if (!canStart && !expired) return null
    return (
      <button
        className="rounded bg-terracotta-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-terracotta-700 disabled:cursor-not-allowed disabled:opacity-50"
        disabled={isPending}
        onClick={onStart}
        type="button"
      >
        {t("preview_start")}
      </button>
    )
  }

  if (state === "starting") {
    return (
      <span className="inline-flex items-center gap-1.5 text-xs text-gray-500 dark:text-gray-400">
        <Spinner />
        {t("preview_starting")}
      </span>
    )
  }

  if (state === "seeding") {
    return (
      <span className="inline-flex items-center gap-1.5 text-xs text-gray-500 dark:text-gray-400">
        <Spinner />
        {t("preview_seeding")}
      </span>
    )
  }

  if (state === "stopping") {
    return (
      <span className="inline-flex items-center gap-1.5 text-xs text-gray-500 dark:text-gray-400">
        <Spinner />
        {t("preview_stopping")}
      </span>
    )
  }

  if (state === "running") {
    if (expired) {
      return (
        <button
          className="rounded bg-terracotta-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-terracotta-700 disabled:cursor-not-allowed disabled:opacity-50"
          disabled={isPending}
          onClick={onStart}
          type="button"
        >
          {t("preview_restart")}
        </button>
      )
    }

    return (
      <div className="flex flex-wrap items-center gap-2">
        <a
          className="rounded bg-emerald-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-emerald-700"
          href={env!.url ?? "#"}
          rel="noopener noreferrer"
          target="_blank"
        >
          {t("preview_open")}
        </a>
        <button
          className="rounded border border-gray-300 px-3 py-1.5 text-xs font-medium text-gray-700 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-800"
          disabled={isPending}
          onClick={onStop}
          type="button"
        >
          {t("preview_stop")}
        </button>
      </div>
    )
  }

  return null
}

function Spinner() {
  return (
    <svg aria-hidden="true" className="h-3 w-3 animate-spin text-gray-400" fill="none" viewBox="0 0 24 24">
      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
      <path className="opacity-75" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" fill="currentColor" />
    </svg>
  )
}

export function PreviewStopModal({
  onStop,
  onKeepRunning
}: {
  onStop: () => void
  onKeepRunning: () => void
}) {
  const { t } = useT("jobs")
  const cancelRef = useRef<HTMLButtonElement>(null)

  useEffect(() => {
    cancelRef.current?.focus()
    function onKeyDown(e: KeyboardEvent) {
      if (e.key === "Escape") onKeepRunning()
    }
    document.addEventListener("keydown", onKeyDown)
    return () => document.removeEventListener("keydown", onKeyDown)
  }, [onKeepRunning])

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      onClick={onKeepRunning}
    >
      <section
        aria-labelledby="preview-stop-modal-title"
        aria-modal="true"
        className="w-full max-w-md rounded-lg bg-white shadow-xl dark:bg-gray-900"
        onClick={(e) => e.stopPropagation()}
        role="dialog"
      >
        <div className="space-y-4 p-5">
          <h2 className="text-base font-semibold text-gray-900 dark:text-gray-100" id="preview-stop-modal-title">
            {t("preview_stop_on_action_title")}
          </h2>
          <p className="text-sm text-gray-700 dark:text-gray-300">{t("preview_stop_on_action_body")}</p>
          <div className="flex justify-end gap-3">
            <button
              className="rounded border border-gray-300 px-4 py-1.5 text-sm text-gray-700 hover:bg-gray-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-800"
              onClick={onKeepRunning}
              ref={cancelRef}
              type="button"
            >
              {t("preview_keep_running")}
            </button>
            <button
              className="rounded bg-red-600 px-4 py-1.5 text-sm font-medium text-white hover:bg-red-700"
              onClick={onStop}
              type="button"
            >
              {t("preview_stop_yes")}
            </button>
          </div>
        </div>
      </section>
    </div>
  )
}
