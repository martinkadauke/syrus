import { execFile } from "node:child_process"
import { promisify } from "node:util"
import { getBackendMode, getLocalInstall, localStateDir } from "../settings.js"
import {
  composeCommand,
  daemonUp,
  execEnv,
  installedRuntimeApp,
  startRuntimeApp,
  syrusHealthy
} from "./dockerRuntime.js"

const execFileAsync = promisify(execFile)

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms))

const WATCHDOG_INTERVAL_MS = 30_000
const DAEMON_WAIT_POLLS = 90 // × 2s = 180s
const HEALTH_WAIT_POLLS = 60 // × 2s = 120s

export type BackendDiagnosis = "daemon-down" | "containers-down" | "stopped"

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

  for (let poll = 0; poll < DAEMON_WAIT_POLLS; poll += 1) {
    if (await daemonUp()) {
      return true
    }

    await sleep(2_000)
  }

  return false
}

let busy = false

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
    return true
  } catch {
    return false
  } finally {
    busy = false
  }
}

export const restartBackend = async (): Promise<boolean> => {
  await stopBackend()
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
let lastHealthy = true

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
          diagnosis = (await daemonUp()) ? "containers-down" : "daemon-down"
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
