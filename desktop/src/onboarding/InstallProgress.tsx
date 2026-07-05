import { useEffect, useRef } from "react"
import { FooterRow, OnboardingScreen, Spinner } from "./primitives"

const STEP_LABELS: Record<SyrusInstallStepId, string> = {
  runtime_check: "Check the Docker runtime",
  runtime_start: "Start the Docker runtime",
  compose_resolve: "Locate Docker Compose",
  env_check: "Check existing configuration",
  env_generate: "Generate configuration and secrets",
  image_pull: "Download Syrus",
  stack_up: "Start Syrus",
  health: "Wait for Syrus to respond"
}

type InstallProgressProps = {
  steps: SyrusInstallStep[]
  logLines: string[]
  onCancel: () => void
}

const StepGlyph = ({ status }: { status: SyrusInstallStep["status"] }) => {
  if (status === "ok") {
    return <span className="text-emerald-600">✓</span>
  }

  if (status === "skipped") {
    return <span className="text-slate-400">–</span>
  }

  if (status === "running") {
    return <Spinner />
  }

  return <span aria-hidden className="inline-block h-2 w-2 rounded-full bg-slate-300" />
}

export function InstallProgress({ steps, logLines, onCancel }: InstallProgressProps) {
  const logRef = useRef<HTMLPreElement | null>(null)

  useEffect(() => {
    logRef.current?.scrollTo({ top: logRef.current.scrollHeight })
  }, [logLines])

  return (
    <OnboardingScreen
      title="Installing Syrus…"
      subtitle="This usually takes a few minutes; downloading the image is the long part."
    >
      <ul className="mt-6 space-y-2" aria-live="polite">
        {steps.map((step) => (
          <li
            key={step.id}
            className="flex items-center gap-3 rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm shadow-sm"
          >
            <span className="flex w-4 justify-center">
              <StepGlyph status={step.status} />
            </span>
            <span className={step.status === "pending" ? "text-slate-400" : "text-slate-800"}>
              {STEP_LABELS[step.id]}
            </span>
          </li>
        ))}
      </ul>

      <details className="mt-4">
        <summary className="cursor-pointer text-xs text-slate-500">Show details</summary>
        <pre
          ref={logRef}
          className="mt-2 max-h-40 overflow-y-auto rounded-lg bg-slate-900 p-3 text-xs leading-relaxed text-slate-200"
        >
          {logLines.join("\n")}
        </pre>
      </details>

      <FooterRow>
        <button type="button" className="secondary-button" onClick={onCancel}>
          Cancel
        </button>
      </FooterRow>
    </OnboardingScreen>
  )
}
