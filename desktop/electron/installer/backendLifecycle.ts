import { execFile, spawn } from "node:child_process"
import { createWriteStream } from "node:fs"
import fs from "node:fs/promises"
import path from "node:path"
import readline from "node:readline"
import { promisify } from "node:util"
import { getBackendMode, getLocalInstall, localStateDir } from "../settings.js"
import {
  composeCommand,
  daemonUp,
  execEnv,
  installedRuntimeApp,
  startRuntimeApp,
  syrusHealthy,
  volumeExists
} from "./dockerRuntime.js"
import { removeSupersededSyrusImages } from "./imageCleanup.js"
import { installerCommand, installerScriptPath } from "./installPaths.js"
import { DATA_VOLUME_NAME } from "./installerDriver.js"
import { BackendUpdateProgressTracker, type BackendUpdateProgress } from "./updateProgress.js"

export type { BackendUpdateProgress } from "./updateProgress.js"

const execFileAsync = promisify(execFile)

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms))

const WATCHDOG_INTERVAL_MS = 30_000
const DAEMON_WAIT_DEADLINE_MS = 180_000
const HEALTH_WAIT_POLLS = 60 // × 2s = 120s

// "data-gone" means Docker is healthy but the Syrus data volume no longer
// exists (wiped containers/volumes) — the stack can never recover on its own.
export type BackendDiagnosis = "daemon-down" | "containers-down" | "stopped" | "data-gone"

const stateDir = () => getLocalInstall()?.stateDir ?? localStateDir()
const port = () => getLocalInstall()?.port ?? 3000

// The install copied docker-compose.yml + .env into the state dir, so plain
// compose invocations from there see the pinned image and the right env.
// Never `down` (that deletes containers; -v would delete data), and never
// `pull` here — image updates happen only through the installer.
const compose = async (args: string[], timeout = 120_000) => {
  const command = await composeCommand()
  if (!command) {
    throw new Error("Docker Compose is not available.")
  }

  const [binary, ...prefixArgs] = command
  await execFileAsync(binary, [...prefixArgs, "-p", "syrus", ...args], {
    cwd: stateDir(),
    env: execEnv(),
    timeout
  })
}

export const backendHealthy = () => syrusHealthy(port())

const ensureDaemon = async () => {
  if (await daemonUp()) {
    return true
  }

  const runtimeApp = installedRuntimeApp()
  if (!runtimeApp) {
    return false
  }

  try {
    await startRuntimeApp(runtimeApp)
  } catch {
    return false
  }

  // Wall-clock deadline with a short per-poll probe: a wedged daemon can
  // hang `docker info` for its full timeout, so an iteration-counted loop
  // with 10s probes silently stretched "3 minutes" to ~18.
  const deadline = Date.now() + DAEMON_WAIT_DEADLINE_MS
  while (Date.now() < deadline) {
    if (await daemonUp(2_000)) {
      return true
    }

    await sleep(2_000)
  }

  return false
}

let busy = false
let lastHealthy = true

export const startBackend = async (): Promise<boolean> => {
  if (getBackendMode() !== "local" || busy) {
    return false
  }

  busy = true
  try {
    if (!(await ensureDaemon())) {
      return false
    }

    await compose(["up", "-d"])

    for (let poll = 0; poll < HEALTH_WAIT_POLLS; poll += 1) {
      if (await backendHealthy()) {
        return true
      }

      await sleep(2_000)
    }

    return false
  } catch {
    return false
  } finally {
    busy = false
  }
}

export const stopBackend = async (): Promise<boolean> => {
  if (getBackendMode() !== "local" || busy) {
    return false
  }

  busy = true
  try {
    await compose(["stop"])
    // A deliberate stop is not an outage: pre-marking the transition keeps
    // the watchdog from overwriting the "stopped" status page with a
    // "containers-down" failure within the next tick.
    lastHealthy = false
    return true
  } catch {
    return false
  } finally {
    busy = false
  }
}

// The SYRUS_IMAGE pin the local install actually runs; null when .env is
// missing or has no pin (pre-pin installs float on :latest).
export const currentImagePin = async (): Promise<string | null> => {
  try {
    const contents = await fs.readFile(path.join(stateDir(), ".env"), "utf8")
    return contents.match(/^SYRUS_IMAGE=(.*)$/m)?.[1]?.trim() || null
  } catch {
    return null
  }
}

// The update's live progress feed for the web sidebar: called with each new
// phase/percent snapshot, then with null once the update ends (either way).
// Progress is strictly cosmetic — a throwing callback must never be able to
// fail or wedge the update itself.
type UpdateBackendDeps = {
  onProgress?: (progress: BackendUpdateProgress | null) => void
}

// Applies a new pinned image by re-running the bundled installer against the
// existing state dir — the same audited path a fresh install takes: rewrite
// the SYRUS_IMAGE pin, pull, recreate containers, health-gate. Output appends
// to install.log so Backend → Open Install Log covers updates too.
export const updateBackend = async (image: string, deps: UpdateBackendDeps = {}): Promise<boolean> => {
  if (getBackendMode() !== "local" || busy) {
    return false
  }

  busy = true
  const report = (progress: BackendUpdateProgress | null) => {
    try {
      deps.onProgress?.(progress)
    } catch {
      // Progress display must never break the update.
    }
  }
  try {
    const tracker = new BackendUpdateProgressTracker()
    // Report "starting" before the daemon wait so the sidebar notice covers
    // the whole outage window, not just the installer's own runtime.
    report(tracker.snapshot())
    if (!(await ensureDaemon())) {
      return false
    }

    const env = execEnv()
    // Test-pacing overrides are for onboarding-driver specs only.
    delete env.SYRUS_HEALTH_POLLS
    delete env.SYRUS_PULL_RETRY_DELAY

    const log = createWriteStream(path.join(stateDir(), "install.log"), { flags: "a" })
    try {
      const ok = await new Promise<boolean>((resolve) => {
        // Same platform-selected interpreter as the onboarding driver — the
        // image-update path IS the installer (bash install.sh on POSIX,
        // powershell install.ps1 on Windows).
        const { command, args } = installerCommand(installerScriptPath(), [
          "--docker",
          "--non-interactive",
          "--json",
          "--skip-runtime-install",
          "--target-dir",
          stateDir(),
          "--image",
          image
        ])
        const child = spawn(command, args, { env, windowsHide: true })
        // Parse the installer's --json NDJSON line-by-line (the same protocol
        // the onboarding driver consumes) so the update reports phases and
        // docker-pull percentages; every raw line still lands in install.log.
        readline.createInterface({ input: child.stdout }).on("line", (line) => {
          log.write(`${line}\n`)
          const progress = tracker.observeLine(line)
          if (progress) {
            report(progress)
          }
        })
        readline.createInterface({ input: child.stderr }).on("line", (line) => {
          log.write(`${line}\n`)
        })
        child.on("error", () => resolve(false))
        // "close", not "exit": close fires only after stdio has drained, so
        // the final NDJSON lines are parsed and nothing writes after end().
        child.on("close", (code) => resolve(code === 0))
      })

      // Superseded-image cleanup runs ONLY on the update path (first installs
      // go through the onboarding driver and have nothing to retire) and only
      // once the stack is re-confirmed healthy on the new pin — a stack left
      // stopped by a wedged update keeps all its images. Each auto-update
      // otherwise strands a multi-GB syrus-backend image on the Docker VM
      // disk until it fills. Best-effort by contract: cleanup can never fail
      // the update that triggered it.
      if (ok && (await backendHealthy())) {
        await removeSupersededSyrusImages({
          pinnedRef: image,
          log: (line) => log.write(`${line}\n`)
        })
      }

      return ok
    } finally {
      log.end()
    }
  } catch {
    return false
  } finally {
    // The notice must disappear on EVERY exit — success, failure, or throw.
    report(null)
    busy = false
  }
}

export const restartBackend = async (): Promise<boolean> => {
  const stopped = await stopBackend()
  if (!stopped) {
    return false
  }

  return startBackend()
}

// On app launch: quitting the app leaves the stack running by design, so
// most launches find a healthy backend and this is a single /up probe.
export const ensureRunning = async () => {
  if (getBackendMode() !== "local") {
    return
  }

  if (await backendHealthy()) {
    return
  }

  await startBackend()
}

type WatchdogDeps = {
  onHealthyChanged: (healthy: boolean, diagnosis: BackendDiagnosis | null) => void
}

let watchdogTimer: NodeJS.Timeout | null = null
let watchdogTickInFlight = false

// Reports transitions only; it never auto-restarts (a crash-looping stack
// would otherwise fight the user). Recovery actions live in the Backend
// menu, and the web window reloads itself once /up answers again.
export const startWatchdog = (deps: WatchdogDeps) => {
  if (watchdogTimer) {
    return
  }

  watchdogTimer = setInterval(() => {
    if (watchdogTickInFlight || busy || getBackendMode() !== "local") {
      return
    }

    watchdogTickInFlight = true
    void (async () => {
      try {
        const healthy = await backendHealthy()
        if (healthy === lastHealthy) {
          return
        }

        lastHealthy = healthy
        let diagnosis: BackendDiagnosis | null = null
        if (!healthy) {
          if (!(await daemonUp())) {
            diagnosis = "daemon-down"
          } else if (!(await volumeExists(DATA_VOLUME_NAME))) {
            diagnosis = "data-gone"
          } else {
            diagnosis = "containers-down"
          }
        }

        deps.onHealthyChanged(healthy, diagnosis)
      } finally {
        watchdogTickInFlight = false
      }
    })()
  }, WATCHDOG_INTERVAL_MS)
}

export const stopWatchdog = () => {
  if (watchdogTimer) {
    clearInterval(watchdogTimer)
    watchdogTimer = null
  }
}
