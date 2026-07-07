import { useEffect, useRef, useState } from "react"
import { useQueryClient } from "@tanstack/react-query"
import { testGeminiKey, updateCredentials } from "../api/credentials"
import { openInNewTab } from "../lib/desktopShell"
import { CloseIcon } from "./CloseIcon"

// Gemini onboarding, invoked lazily the first time it matters — the user
// dragged a video or hit "Record a walkthrough" without a key. Mirrors the
// ConfigureAgentModal experience: paste, staged animated validation, save,
// and hand control straight back to whatever the user was doing.
//
// API key only, by design: server-side video needs the Files API, which the
// gemini-cli OAuth (Code Assist) path does not expose — and reusing that
// OAuth client in third-party apps violates Google's ToS. AI Studio keys are
// free (no card) and validate with a free models.list ping.

type StageStatus = "pending" | "running" | "ok" | "failed"

export type ValidationStage = {
  key: "format" | "reach" | "video"
  status: StageStatus
  detail?: string
}

// Client-side sanity gate before any network call: AI Studio keys are long
// machine tokens (historically `AIza...`, newer keys `AQ....`) — the check is
// deliberately loose (Google evolves prefixes) and exists to catch obvious
// paste accidents (an email address, a fragment), not to police format.
export function looksLikeGeminiKey(value: string): boolean {
  const key = value.trim()
  return key.length >= 20 && !key.includes(" ") && /^[A-Za-z0-9._-]+$/.test(key)
}

const INITIAL_STAGES: ValidationStage[] = [
  { key: "format", status: "pending" },
  { key: "reach", status: "pending" },
  { key: "video", status: "pending" }
]

export function GeminiSetupSheet({
  onClose,
  onConfigured,
  labels
}: {
  onClose: () => void
  onConfigured: () => void
  labels: {
    title: string
    intro: string
    getKey: string
    keyPlaceholder: string
    validateAndSave: string
    validating: string
    stageFormat: string
    stageReach: string
    stageVideo: string
    saved: string
    keyHelp: string
  }
}) {
  const queryClient = useQueryClient()
  const [key, setKey] = useState("")
  const [stages, setStages] = useState<ValidationStage[]>(INITIAL_STAGES)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [saved, setSaved] = useState(false)
  const inputRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    inputRef.current?.focus()
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") onClose()
    }
    document.addEventListener("keydown", onKeyDown)
    return () => document.removeEventListener("keydown", onKeyDown)
  }, [onClose])

  function setStage(stageKey: ValidationStage["key"], status: StageStatus, detail?: string) {
    setStages((current) => current.map((stage) => (stage.key === stageKey ? { ...stage, status, detail } : stage)))
  }

  async function validateAndSave() {
    if (busy) return
    setError(null)
    setSaved(false)
    setStages(INITIAL_STAGES.map((stage) => ({ ...stage })))
    setBusy(true)

    try {
      // Stage 1: format sanity — instant, client-side. A tiny theatrical
      // pause keeps the cascade legible (each check visibly completes).
      setStage("format", "running")
      await pause(350)
      if (!looksLikeGeminiKey(key)) {
        setStage("format", "failed")
        setError(labels.keyHelp)
        return
      }
      setStage("format", "ok")

      // Stage 2 + 3 ride the same free models.list probe: reachability/auth,
      // then whether a video-capable flash model is actually available.
      setStage("reach", "running")
      const payload = await testGeminiKey(key.trim())
      const result = payload.credential_test
      if (!result.ok) {
        const videoProblem = /video-capable/i.test(result.message || "")
        setStage("reach", videoProblem ? "ok" : "failed")
        if (videoProblem) {
          setStage("video", "running")
          await pause(250)
          setStage("video", "failed")
        }
        setError(result.message || "Google rejected this key.")
        return
      }
      setStage("reach", "ok")

      setStage("video", "running")
      await pause(350)
      const model = (result.details as { model?: string } | undefined)?.model
      setStage("video", "ok", model)

      await updateCredentials({ gemini_api_key: key.trim() } as never)
      await queryClient.invalidateQueries({ queryKey: ["credentials"] })
      await queryClient.invalidateQueries({ queryKey: ["bootstrap"] })
      setSaved(true)
      // A beat to let the ✓ cascade land, then hand control back.
      await pause(600)
      onConfigured()
    } catch (err) {
      setStage("reach", "failed")
      setError(err instanceof Error ? err.message : "Could not verify the key. Try again.")
    } finally {
      setBusy(false)
    }
  }

  const stageLabels: Record<ValidationStage["key"], string> = {
    format: labels.stageFormat,
    reach: labels.stageReach,
    video: labels.stageVideo
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" onClick={onClose} role="presentation">
      <section
        aria-labelledby="gemini-setup-title"
        aria-modal="true"
        className="w-full max-w-md rounded-lg border border-gray-200 bg-white p-5 shadow-xl dark:border-gray-700 dark:bg-gray-950"
        onClick={(event) => event.stopPropagation()}
        role="dialog"
      >
        <div className="flex items-start justify-between gap-3">
          <h2 className="text-base font-semibold text-gray-900 dark:text-gray-100" id="gemini-setup-title">
            {labels.title}
          </h2>
          <button aria-label="Close" className="rounded p-1 text-gray-400 hover:bg-gray-100 hover:text-gray-600 dark:hover:bg-gray-800" onClick={onClose} type="button">
            <CloseIcon className="h-4 w-4" />
          </button>
        </div>

        <p className="mt-2 text-sm leading-relaxed text-gray-600 dark:text-gray-300">{labels.intro}</p>

        <button
          className="mt-3 text-sm font-medium text-terracotta-700 underline hover:text-terracotta-800 dark:text-terracotta-300"
          onClick={() => openInNewTab("https://aistudio.google.com/apikey")}
          type="button"
        >
          {labels.getKey}
        </button>

        <form
          className="mt-4"
          onSubmit={(event) => {
            event.preventDefault()
            void validateAndSave()
          }}
        >
          <input
            aria-label={labels.keyPlaceholder}
            autoComplete="off"
            className="w-full rounded border border-gray-300 px-3 py-2 font-mono text-sm focus:border-terracotta-500 focus:ring-terracotta-500 dark:border-gray-600 dark:bg-gray-900 dark:text-gray-100"
            disabled={busy || saved}
            onChange={(event) => setKey(event.target.value)}
            placeholder={labels.keyPlaceholder}
            ref={inputRef}
            spellCheck={false}
            type="password"
            value={key}
          />

          <ul className="mt-4 space-y-2" data-testid="gemini-validation-stages">
            {stages.map((stage) => (
              <li className="flex items-center gap-2 text-sm" data-status={stage.status} data-testid={`gemini-stage-${stage.key}`} key={stage.key}>
                <StageIcon status={stage.status} />
                <span
                  className={
                    stage.status === "failed"
                      ? "text-red-700 dark:text-red-300"
                      : stage.status === "ok"
                        ? "text-emerald-700 dark:text-emerald-300"
                        : "text-gray-600 dark:text-gray-300"
                  }
                >
                  {stageLabels[stage.key]}
                  {stage.detail ? <span className="ml-1 text-xs text-gray-400">({stage.detail})</span> : null}
                </span>
              </li>
            ))}
          </ul>

          {error ? (
            <p className="mt-3 text-sm text-red-700 dark:text-red-300" role="alert">
              {error}
            </p>
          ) : null}
          {saved ? (
            <p className="mt-3 text-sm text-emerald-700 dark:text-emerald-300" role="status">
              {labels.saved}
            </p>
          ) : null}

          <div className="mt-4 flex justify-end">
            <button
              className="rounded bg-terracotta-600 px-4 py-2 text-sm font-semibold text-white hover:bg-terracotta-700 disabled:opacity-50"
              disabled={busy || saved || key.trim().length === 0}
              type="submit"
            >
              {busy ? labels.validating : labels.validateAndSave}
            </button>
          </div>
        </form>
      </section>
    </div>
  )
}

function StageIcon({ status }: { status: StageStatus }) {
  if (status === "running") {
    return (
      <span aria-hidden="true" className="inline-block h-4 w-4 animate-spin rounded-full border-2 border-terracotta-500 border-t-transparent" />
    )
  }
  if (status === "ok") {
    return (
      <span aria-hidden="true" className="inline-flex h-4 w-4 items-center justify-center rounded-full bg-emerald-100 text-[10px] font-bold text-emerald-700 dark:bg-emerald-900 dark:text-emerald-300">
        ✓
      </span>
    )
  }
  if (status === "failed") {
    return (
      <span aria-hidden="true" className="inline-flex h-4 w-4 items-center justify-center rounded-full bg-red-100 text-[10px] font-bold text-red-700 dark:bg-red-900 dark:text-red-300">
        ✕
      </span>
    )
  }
  return <span aria-hidden="true" className="inline-block h-4 w-4 rounded-full border-2 border-gray-200 dark:border-gray-700" />
}

function pause(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}
