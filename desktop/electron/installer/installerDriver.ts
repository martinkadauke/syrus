import { execFile, spawn, type ChildProcess } from "node:child_process"
import { createWriteStream } from "node:fs"
import fs from "node:fs/promises"
import path from "node:path"
import readline from "node:readline"
import { promisify } from "node:util"
import { dialog, shell, type BrowserWindow } from "electron"
import { localStateDir, saveBackendConfig } from "../settings.js"
import { analyzeInstanceUrl } from "./instanceUrl.js"
import { installerCommand, installerScriptPath, readBackendManifest } from "./installPaths.js"
import {
  composeCommand,
  daemonUp,
  execEnv,
  findDockerBinary,
  installedRuntimeApp,
  portInUse,
  startRuntimeApp,
  syrusHealthy,
  volumeExists
} from "./dockerRuntime.js"

const execFileAsync = promisify(execFile)

export const ORBSTACK_DOWNLOAD_URL = "https://orbstack.dev/download"
export const DOCKER_DESKTOP_DOWNLOAD_URL = "https://www.docker.com/products/docker-desktop/"

// The per-platform runtime recommendation the guided setup points at:
// OrbStack on macOS, Docker Desktop on Windows (its installer owns the
// WSL 2 setup). RuntimeSetup.tsx renders the matching copy.
export const runtimeDownloadUrl = () =>
  process.platform === "win32" ? DOCKER_DESKTOP_DOWNLOAD_URL : ORBSTACK_DOWNLOAD_URL
export const DATA_VOLUME_NAME = "syrus_syrus-data"
const DEFAULT_PORT = 3000
const RUNTIME_START_POLLS = 90 // × 2s = 180s, matches install.sh's own wait
const RUNTIME_DOWNLOAD_POLLS = 300 // × 2s = 10 minutes for a manual OrbStack install
const LOG_TAIL_LIMIT = 400

// The install steps install.sh emits in --json mode, in order.
// runtime_install never appears: the app always passes --skip-runtime-install
// and owns runtime acquisition through the guided OrbStack flow.
export const INSTALL_STEP_IDS = [
  "runtime_check",
  "runtime_start",
  "compose_resolve",
  "env_check",
  "env_generate",
  "image_pull",
  "stack_up",
  "health"
] as const

export type InstallStepId = (typeof INSTALL_STEP_IDS)[number]
export type InstallStepStatus = "pending" | "running" | "ok" | "skipped"
export type InstallStep = { id: InstallStepId; status: InstallStepStatus }

export type OnboardingState =
  | { phase: "welcome" }
  | { phase: "connect.form"; error: string | null }
  | { phase: "connect.checking"; url: string }
  | { phase: "local.precheck" }
  | { phase: "local.adoptRunning"; url: string }
  | { phase: "local.adoptExisting"; error: string | null }
  | { phase: "local.runtimeMissing"; polling: boolean }
  | { phase: "local.runtimeStarting" }
  | { phase: "local.portConflict"; port: number }
  | { phase: "local.installing"; steps: InstallStep[]; currentStep: InstallStepId | null }
  | { phase: "local.failed"; code: number; step: string | null; message: string; logTail: string[] }
  | { phase: "done"; mode: "local" | "remote"; url: string }

type InstallerEvent = {
  event: "start" | "step" | "log" | "error" | "done"
  id?: string
  status?: string
  stream?: string
  line?: string
  code?: number
  step?: string
  message?: string
  url?: string
}

type DriverDeps = {
  onState: (state: OnboardingState) => void
  onLogLine: (line: string) => void
}

const errorMessage = (error: unknown, fallback: string) =>
  error instanceof Error && error.message.trim() !== "" ? error.message : fallback

const normalizeUrl = (url: string) => url.trim().replace(/\/+$/, "")

// "Is this URL a Syrus instance?" without needing credentials: the auth
// status endpoint is unauthenticated JSON on every Syrus install. Failure
// messages are classified so the connect form can say what to actually do.
const fingerprintSyrus = async (url: string) => {
  let response: Response
  try {
    response = await fetch(`${url}/api/v1/app/auth/status`, { signal: AbortSignal.timeout(5_000) })
  } catch {
    throw new Error(
      `Nothing answered at ${url}. Check that Syrus is running there and the address and port are right — Syrus usually listens on :3000.`
    )
  }

  // Rails host authorization rejects hostnames it doesn't know — the fix is
  // on the server, so say so instead of a generic "doesn't look like Syrus".
  if (response.status === 403) {
    throw new Error(
      `The server at ${url} refused this hostname. Add it to SYRUS_ALLOWED_HOSTS in the instance's .env (comma-separated), restart Syrus, and try again.`
    )
  }

  if (!response.ok) {
    throw new Error(`Something answered at ${url}, but it doesn't look like a Syrus instance.`)
  }

  try {
    const payload = (await response.json()) as { authenticated?: unknown }
    if (typeof payload.authenticated !== "boolean") {
      throw new Error("shape")
    }
  } catch {
    throw new Error(`Something answered at ${url}, but it doesn't look like a Syrus instance.`)
  }
}

const parsePortFromEnv = (contents: string) => {
  const match = contents.match(/^SYRUS_PORT=(\d+)$/m)
  if (!match) {
    return DEFAULT_PORT
  }

  const port = Number.parseInt(match[1], 10)
  return Number.isFinite(port) && port > 0 ? port : DEFAULT_PORT
}

const portFromUrl = (url: string): number | null => {
  try {
    const parsed = new URL(url)
    const port = Number.parseInt(parsed.port || (parsed.protocol === "https:" ? "443" : "80"), 10)
    return Number.isFinite(port) && port > 0 ? port : null
  } catch {
    return null
  }
}

// "Does this URL actually serve Syrus?" — a bare 200 from /up is not enough
// (every Rails 7.1+ app ships /up).
const isSyrusInstance = async (url: string) => {
  try {
    await fingerprintSyrus(url)
    return true
  } catch {
    return false
  }
}

export class OnboardingDriver {
  private state: OnboardingState = { phase: "welcome" }
  private child: ChildProcess | null = null
  private cancelRequested = false
  private pollTimer: NodeJS.Timeout | null = null
  private port = DEFAULT_PORT
  private logTail: string[] = []
  private lastError: { code: number; step: string | null; message: string } | null = null
  private doneUrl: string | null = null

  constructor(private deps: DriverDeps) {}

  getState() {
    return this.state
  }

  private setState(state: OnboardingState) {
    this.state = state
    this.deps.onState(state)
  }

  backToWelcome() {
    this.stopPolling()
    if (this.child) {
      this.cancelRequested = true
      this.killInstallChild()
      return // handleExit finishes the transition once the child dies
    }

    this.setState({ phase: "welcome" })
  }

  chooseMode(mode: "local" | "remote") {
    this.stopPolling()
    if (mode === "remote") {
      this.setState({ phase: "connect.form", error: null })
      return
    }

    void this.precheck()
  }

  // URL-only by design: sign-in happens in the app window afterwards, and
  // the tray token is minted from that session (tokenProvisioner). Bare
  // hosts/IPs are accepted — analyzeInstanceUrl assumes http:// and Syrus's
  // default :3000 the same way the form's live preview showed the user.
  async connectRemote(request: { url: string }) {
    const analysis = analyzeInstanceUrl(request.url)
    if (analysis.state === "empty") {
      this.setState({ phase: "connect.form", error: "Enter your Syrus instance address." })
      return
    }

    if (analysis.state === "invalid" || analysis.normalized === null) {
      this.setState({ phase: "connect.form", error: analysis.hint || "That doesn't look like a server address." })
      return
    }

    const serverUrl = normalizeUrl(analysis.normalized)
    this.setState({ phase: "connect.checking", url: serverUrl })

    // Back stays enabled while checking (deliberately — a black-holed host
    // must not be a dead end), so this probe can lose a race against the
    // user navigating away. Re-check the phase AND the url after the await,
    // like startRuntime/openOrbStackDownload do: a stale success must not
    // persist a backend choice the user abandoned, and a stale failure must
    // not yank the wizard out of wherever they went.
    const stillChecking = () => this.state.phase === "connect.checking" && this.state.url === serverUrl

    try {
      await fingerprintSyrus(serverUrl)
      if (!stillChecking()) {
        return
      }
      saveBackendConfig({ mode: "remote", serverUrl })
      this.setState({ phase: "done", mode: "remote", url: serverUrl })
    } catch (error) {
      if (!stillChecking()) {
        return
      }
      this.setState({ phase: "connect.form", error: errorMessage(error, "Could not connect to that address.") })
    }
  }

  // The decision tree for "Install Syrus on this Mac". Ordering matters:
  // Syrus-on-port needs no docker; the volume check needs the daemon up.
  async precheck() {
    this.stopPolling()
    this.setState({ phase: "local.precheck" })

    const stateDir = localStateDir()
    const envPath = path.join(stateDir, ".env")
    let hasEnv = false
    try {
      const contents = await fs.readFile(envPath, "utf8")
      hasEnv = true
      this.port = parsePortFromEnv(contents)
    } catch {
      this.port = DEFAULT_PORT
    }

    // A healthy Syrus already answering that we don't own: offer to adopt it
    // as remote-at-localhost (no lifecycle control) instead of clobbering.
    // Fingerprinted — a foreign app's /up must not masquerade as Syrus.
    if (!hasEnv && (await syrusHealthy(this.port))) {
      const localUrl = `http://localhost:${this.port}`
      if (await isSyrusInstance(localUrl)) {
        this.setState({ phase: "local.adoptRunning", url: localUrl })
        return
      }
    }

    const binary = await findDockerBinary()
    if (!binary) {
      if (installedRuntimeApp()) {
        await this.startRuntime()
        return
      }

      this.setState({ phase: "local.runtimeMissing", polling: false })
      return
    }

    if (!(await daemonUp())) {
      await this.startRuntime()
      return
    }

    // The encryption-key guard, surfaced before install.sh would exit 20:
    // a data volume encrypted with keys from a .env we don't have.
    if (!hasEnv && (await volumeExists(DATA_VOLUME_NAME))) {
      this.setState({ phase: "local.adoptExisting", error: null })
      return
    }

    // Port-conflict resolution is only meaningful for a fresh install: with
    // an existing .env the port is owned by that file (install.sh ignores
    // --port), and a busy-but-unhealthy port there is usually our own stack
    // still booting — let the install proceed; a genuine foreign bind
    // surfaces as compose exit 40.
    if (!hasEnv && !(await syrusHealthy(this.port)) && (await portInUse(this.port))) {
      this.setState({ phase: "local.portConflict", port: this.port })
      return
    }

    await this.startInstall()
  }

  private async startRuntime() {
    const runtimeApp = installedRuntimeApp()
    if (!runtimeApp) {
      this.setState({ phase: "local.runtimeMissing", polling: false })
      return
    }

    this.setState({ phase: "local.runtimeStarting" })
    try {
      await startRuntimeApp(runtimeApp)
    } catch {
      // The poll below reports failure either way.
    }

    const ready = await this.pollForDaemon(RUNTIME_START_POLLS)
    if (this.state.phase !== "local.runtimeStarting") {
      return // user navigated away while we waited
    }

    if (ready) {
      void this.precheck()
    } else {
      this.setState({
        phase: "local.failed",
        code: 11,
        step: "runtime_start",
        message: `${runtimeApp} is installed but its Docker daemon never became ready. Open it, finish any setup prompt, then retry.`,
        logTail: []
      })
    }
  }

  // Named for the IPC channel it serves; the URL is per-platform (OrbStack
  // on macOS, Docker Desktop on Windows).
  openOrbStackDownload() {
    void shell.openExternal(runtimeDownloadUrl())
    if (this.state.phase === "local.runtimeMissing" && !this.state.polling) {
      this.setState({ phase: "local.runtimeMissing", polling: true })
      void this.pollForDaemon(RUNTIME_DOWNLOAD_POLLS).then((ready) => {
        if (this.state.phase !== "local.runtimeMissing") {
          return
        }

        if (ready) {
          void this.precheck()
        } else {
          this.setState({ phase: "local.runtimeMissing", polling: false })
        }
      })
    }
  }

  private pollForDaemon(maxPolls: number): Promise<boolean> {
    this.stopPolling()

    return new Promise((resolve) => {
      let polls = 0
      const tick = async () => {
        if ((await findDockerBinary()) && (await daemonUp())) {
          this.stopPolling()
          resolve(true)
          return
        }

        polls += 1
        if (polls >= maxPolls) {
          this.stopPolling()
          resolve(false)
          return
        }

        this.pollTimer = setTimeout(() => void tick(), 2_000)
      }

      void tick()
    })
  }

  private stopPolling() {
    if (this.pollTimer) {
      clearTimeout(this.pollTimer)
      this.pollTimer = null
    }
  }

  adoptRunning() {
    if (this.state.phase !== "local.adoptRunning") {
      return
    }

    const url = this.state.url
    saveBackendConfig({ mode: "remote", serverUrl: url })
    this.setState({ phase: "done", mode: "remote", url })
  }

  // Copy (never move) the user's original .env into the state dir so the
  // existing data volume stays decryptable, then re-run the checks.
  async locateEnv(parentWindow: BrowserWindow | null) {
    const options: Electron.OpenDialogOptions = {
      title: "Locate your original .env",
      message: "Choose the .env file from your existing Syrus install (usually next to your Syrus checkout).",
      properties: ["openFile", "showHiddenFiles"]
    }
    const result = parentWindow
      ? await dialog.showOpenDialog(parentWindow, options)
      : await dialog.showOpenDialog(options)

    if (result.canceled || result.filePaths.length === 0) {
      return
    }

    try {
      const stateDir = localStateDir()
      await fs.mkdir(stateDir, { recursive: true })
      await fs.copyFile(result.filePaths[0], path.join(stateDir, ".env"))
    } catch (error) {
      // Surface the copy failure on the screen instead of silently
      // re-prechecking into the same state with no explanation.
      this.setState({
        phase: "local.adoptExisting",
        error: errorMessage(error, "Couldn't copy that .env file.")
      })
      return
    }

    await this.precheck()
  }

  // The renderer gates this behind a typed confirmation; one final native
  // dialog stands between the click and `compose down -v`.
  async wipeData(parentWindow: BrowserWindow | null) {
    const options: Electron.MessageBoxOptions = {
      type: "warning",
      buttons: ["Delete all Syrus data", "Cancel"],
      defaultId: 1,
      cancelId: 1,
      message: "Delete the existing Syrus data?",
      detail: "This permanently deletes the Docker volumes holding the previous install's database, clone cache, and search index. There is no undo."
    }
    const confirmation = parentWindow
      ? await dialog.showMessageBox(parentWindow, options)
      : await dialog.showMessageBox(options)

    if (confirmation.response !== 0) {
      return
    }

    const compose = await composeCommand()
    if (compose) {
      try {
        const [command, ...prefixArgs] = compose
        await execFileAsync(command, [...prefixArgs, "-p", "syrus", "down", "-v"], {
          env: execEnv(),
          timeout: 120_000
        })
      } catch {
        // Fall through: the volume may not have containers attached.
      }
    }

    const binary = await findDockerBinary()
    if (binary && (await volumeExists(DATA_VOLUME_NAME))) {
      try {
        await execFileAsync(binary, ["volume", "rm", DATA_VOLUME_NAME, "syrus_syrus-search"], {
          env: execEnv(),
          timeout: 60_000
        })
      } catch {
        // precheck() reports the volume still existing.
      }
    }

    await this.precheck()
  }

  async startInstall(portOverride?: number) {
    if (this.child) {
      return
    }

    const stateDir = localStateDir()
    await fs.mkdir(stateDir, { recursive: true })

    if (typeof portOverride === "number" && Number.isFinite(portOverride) && portOverride > 0) {
      this.port = Math.floor(portOverride)
    }

    const manifest = await readBackendManifest()
    const flags = ["--docker", "--non-interactive", "--json", "--skip-runtime-install", "--target-dir", stateDir]
    if (manifest?.image) {
      flags.push("--image", manifest.image)
    }
    if (this.port !== DEFAULT_PORT) {
      flags.push("--port", String(this.port))
    }

    const steps: InstallStep[] = INSTALL_STEP_IDS.map((id) => ({ id, status: "pending" }))
    this.logTail = []
    this.lastError = null
    this.doneUrl = null
    this.cancelRequested = false
    this.setState({ phase: "local.installing", steps, currentStep: null })

    const logStream = createWriteStream(path.join(stateDir, "install.log"), { flags: "a" })
    logStream.write(`\n--- install started ${new Date().toISOString()} ---\n`)

    // POSIX: detached puts the script's docker/compose grandchildren in one
    // process group, so cancel can signal the whole group instead of
    // orphaning an in-flight multi-GB pull. Windows has no process groups —
    // cancel uses taskkill /T there instead (killInstallChild), and detached
    // would pop a new console. The spec knobs are scrubbed so a stray value
    // in the user's environment can't silently gate a real install.
    const env = execEnv()
    delete env.SYRUS_HEALTH_POLLS
    delete env.SYRUS_PULL_RETRY_DELAY
    const { command, args: spawnArgs } = installerCommand(installerScriptPath(), flags)
    const child =
      process.platform === "win32"
        ? spawn(command, spawnArgs, { env, windowsHide: true })
        : spawn(command, spawnArgs, { env, detached: true })
    this.child = child

    readline.createInterface({ input: child.stdout }).on("line", (line) => {
      logStream.write(`${line}\n`)
      this.handleInstallerEvent(line)
    })

    readline.createInterface({ input: child.stderr }).on("line", (line) => {
      logStream.write(`${line}\n`)
      this.appendLog(line)
    })

    child.on("error", (error) => {
      logStream.write(`spawn error: ${String(error)}\n`)
    })

    // "close", not "exit": close fires only after stdio has drained, so the
    // final NDJSON error/done lines are guaranteed to have been parsed and
    // nothing writes to the log stream after end().
    child.on("close", (code) => {
      this.child = null
      logStream.end()
      this.handleExit(code ?? 1)
    })
  }

  // Kill the whole tree so docker/compose grandchildren die with the script
  // instead of racing a retried install: POSIX signals the detached process
  // group; Windows (no process groups) walks the tree with taskkill /T.
  private killInstallChild() {
    if (!this.child?.pid) {
      return
    }

    if (process.platform === "win32") {
      execFile("taskkill", ["/pid", String(this.child.pid), "/T", "/F"], { windowsHide: true }, () => {})
      return
    }

    try {
      process.kill(-this.child.pid, "SIGTERM")
    } catch {
      this.child.kill("SIGTERM")
    }
  }

  cancelInstall() {
    if (!this.child) {
      return
    }

    this.cancelRequested = true
    this.killInstallChild()
  }

  // Forget all wizard progress so a reopened onboarding starts at Welcome —
  // used by "Run Setup Again…", which clears the backend config.
  reset() {
    this.stopPolling()
    if (this.child) {
      this.cancelRequested = true
      this.killInstallChild()
    }

    this.logTail = []
    this.lastError = null
    this.doneUrl = null
    this.setState({ phase: "welcome" })
  }

  private appendLog(line: string) {
    this.logTail.push(line)
    if (this.logTail.length > LOG_TAIL_LIMIT) {
      this.logTail.shift()
    }

    this.deps.onLogLine(line)
  }

  private handleInstallerEvent(line: string) {
    let event: InstallerEvent
    try {
      event = JSON.parse(line) as InstallerEvent
    } catch {
      this.appendLog(line)
      return
    }

    if (event.event === "log" && typeof event.line === "string") {
      this.appendLog(event.line)
      return
    }

    if (event.event === "error") {
      this.lastError = {
        code: typeof event.code === "number" ? event.code : 1,
        step: typeof event.step === "string" && event.step !== "" ? event.step : null,
        message: typeof event.message === "string" ? event.message : "Install failed."
      }
      return
    }

    if (event.event === "done" && typeof event.url === "string") {
      this.doneUrl = event.url
      return
    }

    if (
      event.event === "step" &&
      this.state.phase === "local.installing" &&
      typeof event.id === "string" &&
      (INSTALL_STEP_IDS as readonly string[]).includes(event.id)
    ) {
      const steps = this.state.steps.map((step): InstallStep => {
        if (step.id !== event.id) {
          return step
        }

        if (event.status === "start") {
          return { ...step, status: "running" }
        }

        if (event.status === "ok" || event.status === "skipped") {
          return { ...step, status: event.status }
        }

        return step
      })
      const currentStep = event.status === "start" ? (event.id as InstallStepId) : this.state.currentStep
      this.setState({ phase: "local.installing", steps, currentStep })
    }
  }

  private handleExit(code: number) {
    if (this.cancelRequested) {
      this.cancelRequested = false
      this.setState({ phase: "welcome" })
      return
    }

    if (code === 0) {
      const stateDir = localStateDir()
      const url = this.doneUrl ?? `http://localhost:${this.port}`
      // The done URL carries the port .env actually owns (install.sh ignores
      // --port when .env pre-exists); deriving localInstall.port from it
      // keeps the lifecycle watchdog probing the port the stack serves.
      const port = portFromUrl(url) ?? this.port
      saveBackendConfig({
        mode: "local",
        serverUrl: url,
        localInstall: { stateDir, port }
      })
      this.setState({ phase: "done", mode: "local", url })
      return
    }

    if (code === 10) {
      this.setState({ phase: "local.runtimeMissing", polling: false })
      return
    }

    // Exit 11 means a runtime exists but its daemon never became ready —
    // the download-OrbStack screen would be misleading here.
    if (code === 11) {
      this.setState({
        phase: "local.failed",
        code,
        step: "runtime_start",
        message:
          "Your Docker runtime is installed but its daemon never became ready. Open it, finish any setup prompt, then retry.",
        logTail: [...this.logTail].slice(-40)
      })
      return
    }

    if (code === 20) {
      this.setState({ phase: "local.adoptExisting", error: null })
      return
    }

    this.setState({
      phase: "local.failed",
      code,
      step: this.lastError?.step ?? null,
      message: this.lastError?.message ?? "The installer failed. Open the log for details.",
      logTail: [...this.logTail].slice(-40)
    })
  }
}
