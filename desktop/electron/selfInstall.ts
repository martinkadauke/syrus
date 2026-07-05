// Codex-style install contract for the DMG: double-clicking Syrus inside the
// mounted image copies it into ~/Applications and relaunches from there — no
// drag target, no dialog. The pure decision helpers are Electron-free so the
// renderer test suite can exercise them.
import { execFile } from "node:child_process"
import fs from "node:fs/promises"
import path from "node:path"
import { promisify } from "node:util"

const execFileAsync = promisify(execFile)

// <bundle>.app/Contents/MacOS/<binary> → <bundle>.app
export const bundlePathFromExecPath = (execPath: string): string =>
  path.resolve(execPath, "..", "..", "..")

export const shouldSelfInstall = ({
  isPackaged,
  platform,
  bundlePath,
  homeDir
}: {
  isPackaged: boolean
  platform: NodeJS.Platform
  bundlePath: string
  homeDir: string
}): boolean => {
  if (!isPackaged || platform !== "darwin") {
    return false
  }

  // Not a normal .app bundle layout — don't guess.
  if (!bundlePath.endsWith(".app")) {
    return false
  }

  const systemApplications = "/Applications"
  const userApplications = path.join(homeDir, "Applications")
  return ![systemApplications, userApplications].some(
    (dir) => bundlePath.startsWith(`${dir}${path.sep}`)
  )
}

export const installedAppPath = (homeDir: string, bundlePath: string): string =>
  path.join(homeDir, "Applications", path.basename(bundlePath))

// Copies the bundle with ditto (preserves the code signature and bundle
// metadata a plain recursive copy would drop), replaces any previous install,
// strips the quarantine flag best-effort, and launches the copy. Returns the
// installed path; throws if the copy cannot be produced.
export const installBundle = async (bundlePath: string, homeDir: string): Promise<string> => {
  const target = installedAppPath(homeDir, bundlePath)
  await fs.mkdir(path.dirname(target), { recursive: true })
  await fs.rm(target, { recursive: true, force: true })
  await execFileAsync("/usr/bin/ditto", [bundlePath, target])
  try {
    await execFileAsync("/usr/bin/xattr", ["-dr", "com.apple.quarantine", target])
  } catch {
    // Best-effort: Gatekeeper may re-prompt on first launch, but the install
    // itself is intact.
  }

  return target
}

// macOS launches .app bundles through open(1); Windows identities carry the
// exe path itself (ownInstanceIdentity sends process.execPath there), which
// can be spawned directly — used by the instance-takeover "Switch" path.
export const launchInstalledCopy = async (target: string): Promise<void> => {
  if (process.platform === "win32") {
    const { spawn } = await import("node:child_process")
    const child = spawn(target, [], { detached: true, stdio: "ignore" })
    child.unref()
    return
  }

  await execFileAsync("/usr/bin/open", ["-n", target])
}
