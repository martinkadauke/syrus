import type { ReactNode, UIEvent } from "react"
import { useEffect, useLayoutEffect, useRef, useState } from "react"
import { Link, useLocation } from "react-router-dom"
import { AnsiText } from "../../components/AnsiText"
import type { JobRun, fetchJobRunArtifacts } from "../../api/jobs"
import { useT } from "../../hooks/useT"
import type { LineAnnotation } from "./diffRendering"
import { diffCoverageBorderClass, diffGutterClass, diffLineClass, diffMarkerClass, parseUnifiedDiff } from "./diffRendering"
import { formatDate, withRoutePrefix } from "./formatting"
import { formatElapsed, humanize } from "./stepModel"
import { coalesceTranscriptLogs, isRunTranscriptAtBottom, scrollRunTranscriptToBottom } from "./transcript"

// Shared presentational micro-components extracted from JobDetail.tsx: the small
// pill/panel primitives, the live-elapsed hook, the active/queued Run banner, and
// the run-transcript log stream. Kept in a leaf module so both the route file and
// the workflow/step/run render subtree can import them without a circular edge.

export function AgentDiff({ diff, annotations }: { diff: string; annotations?: Record<string, LineAnnotation> }) {
  const lines = parseUnifiedDiff(diff)

  return (
    <div className="max-h-[32rem] overflow-auto bg-white font-mono text-xs max-md:min-h-0 max-md:flex-1 max-md:max-h-none dark:bg-gray-950" data-testid="agent-diff-viewer">
      <table className="min-w-full border-separate border-spacing-0">
        <tbody>
          {lines.map((line, index) => {
            const annotation = annotations && line.newLine != null ? annotations[String(line.newLine)] : undefined
            return (
              <tr
                className={diffLineClass(line.kind)}
                data-coverage={annotation}
                data-diff-kind={line.kind}
                key={`${index}-${line.kind}-${line.oldLine || ""}-${line.newLine || ""}`}
              >
                <td className={diffGutterClass(line.kind)}>{line.oldLine ?? ""}</td>
                <td className={diffGutterClass(line.kind)}>{line.newLine ?? ""}</td>
                <td className={diffMarkerClass(line.kind)}>{line.marker}</td>
                <td className={`min-w-[40rem] whitespace-pre px-3 py-0.5 text-gray-900 dark:text-gray-200 ${diffCoverageBorderClass(annotation)}`}>{line.code || " "}</td>
                <td className="w-4 select-none px-1 text-center">
                  {annotation === "covered" ? <span className="text-emerald-600 dark:text-emerald-400">✓</span>
                    : annotation === "uncovered" ? <span className="text-red-600 dark:text-red-400">✗</span>
                    : null}
                </td>
              </tr>
            )
          })}
        </tbody>
      </table>
    </div>
  )
}

export function SmallPill({ children }: { children: ReactNode }) {
  return <span className="inline-flex items-center rounded bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-600 dark:bg-gray-800 dark:text-gray-300">{children}</span>
}

export function PanelMessage({ children, tone = "muted" }: { children: ReactNode; tone?: "muted" | "error" | "success" }) {
  const colors = {
    error: "border-red-200 bg-red-50 text-red-700 dark:border-red-900/70 dark:bg-red-950/40 dark:text-red-200",
    success: "border-green-200 bg-green-50 text-green-700 dark:border-green-900/70 dark:bg-green-950/40 dark:text-green-200",
    muted: "border-gray-200 bg-white text-gray-600 dark:border-gray-700 dark:bg-gray-900 dark:text-gray-300"
  }
  return <div className={`rounded border p-4 text-sm ${colors[tone]}`}>{children}</div>
}

// Live wall-clock, ticking every second while `active`. Used so a
// queued/running Run's elapsed time updates in place.
export function useNow(active: boolean) {
  const [now, setNow] = useState(() => Date.now())
  useEffect(() => {
    if (!active) return undefined
    const id = window.setInterval(() => setNow(Date.now()), 1000)
    return () => window.clearInterval(id)
  }, [active])
  return now
}

// A queued Run hasn't started_at yet — it's waiting for a free worker in
// the SolidQueue pool, NOT "starting the agent". Surface that honestly
// (with how long it's been waiting) so a capacity wait doesn't read as a
// hung job; a running Run shows how long it's been going.
export function ActiveRunBanner({ run }: { run: JobRun }) {
  const { t } = useT("jobs")
  const location = useLocation()
  const prefix = location.pathname.startsWith("/app-shell") ? "/app-shell" : ""
  const queued = run.state === "queued" || !run.started_at
  const now = useNow(true)
  const sinceIso = queued ? run.created_at : run.started_at
  const elapsed = sinceIso ? formatElapsed((now - new Date(sinceIso).getTime()) / 1000) : null
  const activeProcess = run.active_process
  const budgetParts: string[] = []
  if (activeProcess?.wall_timeout_s) {
    budgetParts.push(t("run_active_process_wall_budget", { duration: formatElapsed(activeProcess.wall_timeout_s) }))
  }
  if (activeProcess?.silent_timeout_s) {
    budgetParts.push(t("run_active_process_silent_budget", { duration: formatElapsed(activeProcess.silent_timeout_s) }))
  }

  if (queued) {
    return (
      <div className="mt-2 rounded border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-900 dark:border-amber-900/70 dark:bg-amber-950/40 dark:text-amber-200">
        <span className="font-semibold">{t("run_queued_waiting", { id: run.id })}{elapsed ? ` · ${t("run_queued_suffix", { elapsed })}` : ""}</span>
        <span className="mt-1 block text-amber-700 dark:text-amber-300">
          {t("run_queued_backlog")}{" "}
          <Link className="underline hover:text-amber-900 dark:hover:text-amber-100" to={withRoutePrefix("/admin/queue/pending", prefix)}>{t("run_queued_backlog_link")}</Link> {t("run_queued_backlog_suffix")}
        </span>
      </div>
    )
  }

  return (
    <div className="mt-2 rounded border border-blue-200 bg-blue-50 px-3 py-2 text-xs text-blue-800 dark:border-blue-900/70 dark:bg-blue-950/40 dark:text-blue-200">
      <span className="font-semibold">{t("run_running", { id: run.id })}{elapsed ? ` · ${elapsed}` : ""}</span>
      <span> {t("run_running_suffix", { date: formatDate(run.started_at) })}</span>
      {activeProcess ? (
        <div className="mt-1 flex min-w-0 flex-wrap items-center gap-x-2 gap-y-1 text-blue-700 dark:text-blue-300">
          <span>{t("run_active_process", { kind: humanize(activeProcess.kind) })}</span>
          <code className="max-w-full truncate rounded bg-white/75 px-1.5 py-0.5 font-mono text-[11px] text-blue-950 dark:bg-blue-900/40 dark:text-blue-100">
            {activeProcess.command || t("run_active_process_unknown_command")}
          </code>
          {budgetParts.length > 0 ? <span>{t("run_active_process_budget", { budget: budgetParts.join(" · ") })}</span> : null}
        </div>
      ) : null}
    </div>
  )
}

function transcriptLogKindLabel(kind: string | null | undefined, t: ReturnType<typeof useT>["t"]) {
  if (kind === "assistant_text") return t("transcript_kind_agent")
  if (kind === "tool_call") return t("transcript_kind_tool")
  if (kind === "system") return t("transcript_kind_system")
  return kind
}

export function RunTranscriptLogs({ logs }: { logs: Awaited<ReturnType<typeof fetchJobRunArtifacts>>["logs"] }) {
  const { t } = useT("jobs")
  const listRef = useRef<HTMLOListElement | null>(null)
  const atBottomRef = useRef(true)
  const logSignature = logs.map((log) => `${log.id}:${log.sequence}:${log.kind || ""}:${log.chunk.length}`).join("|")
  const displayLogs = coalesceTranscriptLogs(logs)

  function handleScroll(event: UIEvent<HTMLOListElement>) {
    atBottomRef.current = isRunTranscriptAtBottom(event.currentTarget)
  }

  useLayoutEffect(() => {
    if (atBottomRef.current) scrollRunTranscriptToBottom(listRef.current)
  }, [logSignature])

  return (
    <ol className="max-h-[32rem] overflow-auto divide-y divide-gray-200 max-md:min-h-0 max-md:flex-1 max-md:max-h-none dark:divide-gray-800" data-testid="run-transcript-log-stream" onScroll={handleScroll} ref={listRef}>
      {displayLogs.map((log) => (
        <li className="grid gap-2 px-3 py-2 font-mono text-xs text-gray-800 sm:grid-cols-[5rem_minmax(0,1fr)] dark:text-gray-200" key={log.id}>
          <span className="text-gray-400 dark:text-gray-500">{transcriptLogKindLabel(log.kind, t) || `#${log.sequence}`}</span>
          <pre className="whitespace-pre-wrap break-words"><AnsiText text={log.chunk} /></pre>
        </li>
      ))}
    </ol>
  )
}
