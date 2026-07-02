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
const dockerCandidateDirs = () => [
  path.join(os.homedir(), ".orbstack", "bin"),
  "/opt/homebrew/bin",
  "/usr/local/bin",
  "/Applications/Docker.app/Contents/Resources/bin"
]

export const augmentedPath = () => {
  const extras = dockerCandidateDirs().filter((dir) => fs.existsSync(dir))
  const current = (process.env.PATH ?? "").split(":").filter(Boolean)
  const merged = [...current]
  for (const dir of extras) {
    if (!merged.includes(dir)) {
      merged.push(dir)
    }
  }
  return merged.join(":")
}

export const execEnv = (): NodeJS.ProcessEnv => ({ ...process.env, PATH: augmentedPath() })

let cachedDockerBinary: string | null | undefined

export const findDockerBinary = async (): Promise<string | null> => {
  if (cachedDockerBinary !== undefined && cachedDockerBinary !== null) {
    return cachedDockerBinary
  }

  for (const dir of dockerCandidateDirs()) {
    const candidate = path.join(dir, "docker")
    try {
      fs.accessSync(candidate, fs.constants.X_OK)
      cachedDockerBinary = candidate
      return candidate
    } catch {
      // Try the next candidate location.
    }
  }

  try {
    const { stdout } = await execFileAsync("/usr/bin/which", ["docker"], { env: execEnv() })
    const found = stdout.trim()
    cachedDockerBinary = found === "" ? null : found
  } catch {
    cachedDockerBinary = null
  }

  return cachedDockerBinary
}

export const daemonUp = async (): Promise<boolean> => {
  const binary = await findDockerBinary()
  if (!binary) {
    return false
  }

  try {
    await execFileAsync(binary, ["info"], { env: execEnv(), timeout: 10_000 })
    return true
  } catch {
    return false
  }
}

export type RuntimeApp = "OrbStack" | "Docker Desktop"

export const installedRuntimeApp = (): RuntimeApp | null => {
  if (fs.existsSync("/Applications/OrbStack.app")) {
    return "OrbStack"
  }

  if (fs.existsSync("/Applications/Docker.app")) {
    return "Docker Desktop"
  }

  return null
}

export const startRuntimeApp = async (runtimeApp: RuntimeApp) => {
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
    await execFileAsync("/usr/bin/which", ["docker-compose"], { env: execEnv() })
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
