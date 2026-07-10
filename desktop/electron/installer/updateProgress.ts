// Folds the installer's --json NDJSON stream into the coarse phase +
// percentage view of a backend update the web sidebar shows. updateBackend
// (backendLifecycle.ts) spawns the SAME installer script the onboarding
// driver runs, so the protocol here is the driver's: {event:"step",id,status}
// markers for install.sh's stages and {event:"log",line} wrappers that carry
// `docker compose --progress=json pull` layer objects during image_pull.
//
// The sidebar's phases are deliberately coarser than install.sh's step ids —
// an updating user cares about "downloading / starting / migrating", not
// env_check vs compose_resolve:
//
//   (update begins)      → starting     (runtime/env checks — seconds)
//   image_pull start     → downloading  (+ overall percent from the pull)
//   stack_up start       → starting     (containers recreated on the new pin)
//   health start         → migrating    (the /up wait; on a new image this is
//                                        dominated by db:prepare running the
//                                        migrations, hence the label)
//
// Pure module by design: no electron/node imports, so renderer-side vitest
// (desktop/src/updateProgress.test.ts) can exercise it directly — same
// contract as pullProgress.ts.

import { PullProgressAggregator, parsePullProgressLine } from "./pullProgress.js"

export type BackendUpdatePhase = "starting" | "downloading" | "migrating"

// What crosses the shell-notice bridge (main → webAppPreload → the SPA's
// sidebar). `percent` is only ever non-null during "downloading"; older
// compose versions print plain-text pull progress that never parses, and the
// sidebar degrades to an indeterminate bar.
export type BackendUpdateProgress = { phase: BackendUpdatePhase; percent: number | null }

const STEP_PHASES: Record<string, BackendUpdatePhase> = {
  image_pull: "downloading",
  stack_up: "starting",
  health: "migrating"
}

const parseJsonObject = (line: string): Record<string, unknown> | null => {
  const trimmed = line.trim()
  if (!trimmed.startsWith("{")) {
    return null
  }

  let parsed: unknown
  try {
    parsed = JSON.parse(trimmed)
  } catch {
    return null
  }

  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    return null
  }

  return parsed as Record<string, unknown>
}

export class BackendUpdateProgressTracker {
  private phase: BackendUpdatePhase = "starting"
  private percent: number | null = null
  private pulling = false
  private aggregator = new PullProgressAggregator()

  snapshot(): BackendUpdateProgress {
    return { phase: this.phase, percent: this.percent }
  }

  // One raw installer stdout line → the new progress snapshot when the line
  // changed anything user-visible, or null when it didn't. Callers broadcast
  // each snapshot over IPC, so "no change" must stay cheap and silent —
  // integer-percent changes bound the downloading phase to ≤100 emissions.
  observeLine(rawLine: string): BackendUpdateProgress | null {
    const parsed = parseJsonObject(rawLine)
    if (!parsed) {
      return null
    }

    if (parsed.event === "step" && typeof parsed.id === "string") {
      return this.observeStep(parsed.id, parsed.status)
    }

    if (parsed.event === "log" && typeof parsed.line === "string") {
      return this.observePullLine(parsed.line)
    }

    // Not an install.sh event: if install.sh ever streams compose's
    // --progress=json objects through unwrapped, fold them in the same way
    // the onboarding driver does (otherwise they'd stay invisible).
    if (parsed.event === undefined) {
      return this.observePullLine(rawLine)
    }

    return null
  }

  private observeStep(id: string, status: unknown): BackendUpdateProgress | null {
    if (id === "image_pull") {
      this.pulling = status === "start"
    }

    const phase = STEP_PHASES[id]
    if (!phase || status !== "start" || phase === this.phase) {
      return null
    }

    this.phase = phase
    // The percent belongs to the pull; a later phase must not carry a stale
    // 100% bar into "migrating".
    if (phase !== "downloading") {
      this.percent = null
    }

    return this.snapshot()
  }

  private observePullLine(line: string): BackendUpdateProgress | null {
    if (!this.pulling) {
      return null
    }

    const event = parsePullProgressLine(line)
    if (!event) {
      return null
    }

    this.aggregator.observe(event)
    const percent = this.aggregator.snapshot().percent
    if (percent === null || percent === this.percent) {
      return null
    }

    this.percent = percent
    return this.snapshot()
  }
}
