import { execFile } from "node:child_process"
import fs from "node:fs"
import net from "node:net"
import os from "node:os"
import path from "node:path"
import { promisify } from "node:util"

const execFileAsync = promisify(execFile)

// GUI-launched apps get a minimal PATH (/usr/bin:/bin:...), so `docker` from
// OrbStack, Homebrew, or Docker Desktop is invisible without help. Every
// docker/compose invocation in the app must go through execEnv() or an
// absolute binary path from findDockerBinary().
const dockerCandidateDirs = () =>
  process.platform === "win32"
    ? [
        path.join(process.env["ProgramFiles"] ?? "C:\\Program Files", "Docker", "Docker", "resources", "bin"),
        path.join(process.env["LOCALAPPDATA"] ?? "", "Programs", "RedHat", "Podman")
      ].filter((dir) => dir !== "")
    : [
        path.join(os.homedir(), ".orbstack", "bin"),
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/Applications/Docker.app/Contents/Resources/bin"
      ]

export const augmentedPath = () => {
  const extras = dockerCandidateDirs().filter((dir) => fs.existsSync(dir))
  const current = (process.env.PATH ?? "").split(path.delimiter).filter(Boolean)
  const merged = [...current]
  for (const dir of extras) {
    if (!merged.includes(dir)) {
      merged.push(dir)
    }
  }
  return merged.join(path.delimiter)
}

export const execEnv = (): NodeJS.ProcessEnv => ({ ...process.env, PATH: augmentedPath() })

let cachedDockerBinary: string | null | undefined

export const findDockerBinary = async (): Promise<string | null> => {
  if (cachedDockerBinary !== undefined && cachedDockerBinary !== null) {
    return cachedDockerBinary
  }

  const binaryName = process.platform === "win32" ? "docker.exe" : "docker"
  for (const dir of dockerCandidateDirs()) {
    const candidate = path.join(dir, binaryName)
    try {
      fs.accessSync(candidate, fs.constants.X_OK)
      cachedDockerBinary = candidate
      return candidate
    } catch {
      // Try the next candidate location.
    }
  }

  try {
    const lookup = process.platform === "win32" ? ["where", ["docker"]] as const : ["/usr/bin/which", ["docker"]] as const
    const { stdout } = await execFileAsync(lookup[0], [...lookup[1]], { env: execEnv() })
    const found = stdout.split(/\r?\n/)[0]?.trim() ?? ""
    cachedDockerBinary = found === "" ? null : found
  } catch {
    cachedDockerBinary = null
  }

  return cachedDockerBinary
}

export const daemonUp = async (timeoutMs = 10_000): Promise<boolean> => {
  const binary = await findDockerBinary()
  if (!binary) {
    return false
  }

  try {
    await execFileAsync(binary, ["info"], { env: execEnv(), timeout: timeoutMs })
    return true
  } catch {
    return false
  }
}

export type RuntimeApp = "OrbStack" | "Docker Desktop" | "Colima" | "Podman Desktop"

// Per-platform runtime recommendation for the "no Docker runtime" screen.
// macOS: OrbStack (fast, free for personal use). Windows: Docker Desktop as
// the default happy path, Podman Desktop as the open-source alternative —
// see docs/windows-desktop-plan.md for the reasoning.
export const runtimeRecommendation = () =>
  process.platform === "win32"
    ? {
        name: "Docker Desktop" as const,
        downloadUrl: "https://www.docker.com/products/docker-desktop/",
        alternative: { name: "Podman Desktop" as const, downloadUrl: "https://podman-desktop.io/downloads" }
      }
    : {
        name: "OrbStack" as const,
        downloadUrl: "https://orbstack.dev/download",
        alternative: null
      }

const colimaBinary = (): string | null => {
  for (const dir of ["/opt/homebrew/bin", "/usr/local/bin"]) {
    const candidate = path.join(dir, "colima")
    if (fs.existsSync(candidate)) {
      return candidate
    }
  }

  return null
}

export const installedRuntimeApp = (): RuntimeApp | null => {
  if (process.platform === "win32") {
    const programFiles = process.env["ProgramFiles"] ?? "C:\\Program Files"
    if (fs.existsSync(path.join(programFiles, "Docker", "Docker", "Docker Desktop.exe"))) {
      return "Docker Desktop"
    }
    if (fs.existsSync(path.join(process.env["LOCALAPPDATA"] ?? "", "Programs", "podman-desktop", "Podman Desktop.exe"))) {
      return "Podman Desktop"
    }
    return null
  }

  if (fs.existsSync("/Applications/OrbStack.app")) {
    return "OrbStack"
  }

  if (fs.existsSync("/Applications/Docker.app")) {
    return "Docker Desktop"
  }

  // App-less runtime: a stopped Colima should be started, not treated as
  // "no runtime installed" (which pushes its user to download OrbStack).
  if (colimaBinary()) {
    return "Colima"
  }

  return null
}

export const startRuntimeApp = async (runtimeApp: RuntimeApp) => {
  if (runtimeApp === "Colima") {
    const binary = colimaBinary()
    if (binary) {
      await execFileAsync(binary, ["start"], { env: execEnv(), timeout: 180_000 })
    }
    return
  }

  if (process.platform === "win32") {
    const programFiles = process.env["ProgramFiles"] ?? "C:\\Program Files"
    const exe = runtimeApp === "Docker Desktop"
      ? path.join(programFiles, "Docker", "Docker", "Docker Desktop.exe")
      : path.join(process.env["LOCALAPPDATA"] ?? "", "Programs", "podman-desktop", "Podman Desktop.exe")
    await execFileAsync("cmd.exe", ["/c", "start", "", exe])
    return
  }

  const appName = runtimeApp === "OrbStack" ? "OrbStack" : "Docker"
  await execFileAsync("open", ["-a", appName])
}

// ["/abs/docker", "compose"] for the v2 plugin, ["docker-compose"] for the
// standalone v1 binary, null when neither is available.
export const composeCommand = async (): Promise<string[] | null> => {
  const binary = await findDockerBinary()
  if (binary) {
    try {
      await execFileAsync(binary, ["compose", "version"], { env: execEnv(), timeout: 10_000 })
      return [binary, "compose"]
    } catch {
      // Fall through to the standalone binary.
    }
  }

  try {
    const lookup = process.platform === "win32" ? ["where", ["docker-compose"]] as const : ["/usr/bin/which", ["docker-compose"]] as const
    await execFileAsync(lookup[0], [...lookup[1]], { env: execEnv() })
    return ["docker-compose"]
  } catch {
    return null
  }
}

export const volumeExists = async (name: string): Promise<boolean> => {
  const binary = await findDockerBinary()
  if (!binary) {
    return false
  }

  try {
    await execFileAsync(binary, ["volume", "inspect", name], { env: execEnv(), timeout: 10_000 })
    return true
  } catch {
    return false
  }
}

export const portInUse = (port: number): Promise<boolean> =>
  new Promise((resolve) => {
    const socket = net.connect({ port, host: "127.0.0.1" })
    const finish = (result: boolean) => {
      socket.destroy()
      resolve(result)
    }

    socket.setTimeout(1_000)
    socket.on("connect", () => finish(true))
    socket.on("timeout", () => finish(false))
    socket.on("error", () => finish(false))
  })

export const syrusHealthy = async (port: number): Promise<boolean> => {
  try {
    const response = await fetch(`http://localhost:${port}/up`, { signal: AbortSignal.timeout(2_000) })
    return response.ok
  } catch {
    return false
  }
}
