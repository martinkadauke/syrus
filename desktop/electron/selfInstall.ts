// Install contract for the DMG: double-clicking Syrus inside the mounted
// image installs it into Applications and relaunches from there — no drag
// target. /Applications is preferred; ~/Applications is the admin-free
// fallback. A fresh install is silent, but replacing an existing install
// asks first, naming both versions. Every path ends away from the DMG:
// decline launches the existing install, a failed copy explains the manual
// drag and quits, a failed launch names the installed location and quits.
// The decision helpers are pure and Electron-free so the renderer test
// suite can exercise them.
import { execFile } from "node:child_process"
import fs from "node:fs/promises"
import path from "node:path"
import { promisify } from "node:util"

const execFileAsync = promisify(execFile)

export const SYSTEM_APPLICATIONS = "/Applications"

// package.json ships 0.0.0 outside tag-driven release builds, so 0.0.0 means
// "unknown/dev build" — it must never claim to be newer than a versioned
// install, and never silently downgrade one.
export const UNKNOWN_VERSION = "0.0.0"

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

  const userApplications = path.join(homeDir, "Applications")
  return ![SYSTEM_APPLICATIONS, userApplications].some(
    (dir) => bundlePath.startsWith(`${dir}${path.sep}`)
  )
}

export type InstallTarget = {
  path: string
  existingInstall: boolean
}

// Pure target choice from observed facts: replace the install that already
// exists AND can actually be replaced. /Applications wins when it holds a
// copy and is writable without admin rights; a /Applications copy a standard
// user cannot touch is never targeted (that replace would be a guaranteed
// EACCES dead end) — the ~/Applications copy, existing or fresh, is used
// instead and the admin copy stays; the instance-takeover identity sorts out
// the duality at launch. The non-target copy is never silently deleted.
// Fresh installs go to /Applications when writable, ~/Applications when not.
export const chooseInstallTarget = ({
  bundleName,
  homeDir,
  systemExists,
  userExists,
  systemWritable
}: {
  bundleName: string
  homeDir: string
  systemExists: boolean
  userExists: boolean
  systemWritable: boolean
}): InstallTarget => {
  const systemPath = path.join(SYSTEM_APPLICATIONS, bundleName)
  const userPath = path.join(homeDir, "Applications", bundleName)

  if (systemExists && systemWritable) {
    return { path: systemPath, existingInstall: true }
  }
  if (userExists) {
    return { path: userPath, existingInstall: true }
  }

  return { path: systemWritable ? systemPath : userPath, existingInstall: false }
}

const canAccess = async (target: string, mode?: number): Promise<boolean> => {
  try {
    await fs.access(target, mode)
    return true
  } catch {
    return false
  }
}

// Probes the filesystem, then delegates the decision to the pure chooser.
export const resolveInstallTarget = async (
  bundlePath: string,
  homeDir: string
): Promise<InstallTarget> => {
  const bundleName = path.basename(bundlePath)
  return chooseInstallTarget({
    bundleName,
    homeDir,
    systemExists: await canAccess(path.join(SYSTEM_APPLICATIONS, bundleName)),
    userExists: await canAccess(path.join(homeDir, "Applications", bundleName)),
    systemWritable: await canAccess(SYSTEM_APPLICATIONS, fs.constants.W_OK)
  })
}

// Reads an installed copy's CFBundleShortVersionString. PlistBuddy handles
// both XML and binary plists; defaults(1) is the fallback when PlistBuddy is
// unavailable (it wants the path without the .plist extension). Returns null
// when the version cannot be read — callers treat that as "unknown".
export const installedBundleVersion = async (appPath: string): Promise<string | null> => {
  const plist = path.join(appPath, "Contents", "Info.plist")
  const attempts: Array<[string, string[]]> = [
    ["/usr/libexec/PlistBuddy", ["-c", "Print :CFBundleShortVersionString", plist]],
    ["/usr/bin/defaults", ["read", plist.replace(/\.plist$/, ""), "CFBundleShortVersionString"]]
  ]
  for (const [command, args] of attempts) {
    try {
      const { stdout } = await execFileAsync(command, args)
      const version = stdout.trim()
      if (version !== "") {
        return version
      }
    } catch {
      // Try the next reader.
    }
  }

  return null
}

export type VersionComparison = "newer" | "older" | "same" | "unknown"

const parseVersion = (value: string | null | undefined): number[] | null => {
  const trimmed = value?.trim()
  if (!trimmed || trimmed === UNKNOWN_VERSION) {
    return null
  }

  // Strictly numeric segments only — parseInt would silently truncate
  // "0.1.4-beta.1" to 0.1.4. Prerelease/malformed versions are not
  // comparable and classify as unknown.
  const parts = trimmed.split(".")
  if (parts.length === 0 || !parts.every((part) => /^\d+$/.test(part))) {
    return null
  }

  return parts.map((part) => Number.parseInt(part, 10))
}

// How `candidate` (the launching copy) relates to `existing` (the installed
// copy). 0.0.0, null, or unparseable on EITHER side is "unknown".
export const compareVersions = (
  candidate: string | null | undefined,
  existing: string | null | undefined
): VersionComparison => {
  const left = parseVersion(candidate)
  const right = parseVersion(existing)
  if (!left || !right) {
    return "unknown"
  }

  for (let i = 0; i < Math.max(left.length, right.length); i += 1) {
    const a = left[i] ?? 0
    const b = right[i] ?? 0
    if (a !== b) {
      return a > b ? "newer" : "older"
    }
  }

  return "same"
}

const describeVersion = (version: string | null | undefined): string =>
  parseVersion(version) ? `Syrus ${version?.trim()}` : "an unknown-version dev build"

// Dialog copy for replacing an existing install. Shown BEFORE any copying;
// "Keep Existing" hands over to the already-installed copy.
export const replacePrompt = ({
  existingVersion,
  newVersion,
  targetPath
}: {
  existingVersion: string | null
  newVersion: string
  targetPath: string
}) => {
  const note = {
    newer: " (this copy appears newer)",
    older: " (the installed copy appears newer)",
    same: " (same version)",
    unknown: ""
  }[compareVersions(newVersion, existingVersion)]

  return {
    message: "Install Syrus to Applications?",
    detail:
      `This will replace ${describeVersion(existingVersion)} in ${path.dirname(targetPath)} ` +
      `with ${describeVersion(newVersion)}${note}.\n\n` +
      '"Keep Existing" opens the installed copy instead.',
    buttons: ["Replace", "Keep Existing"] as const,
    replaceIndex: 0,
    cancelId: 1
  }
}

export type InstallDecision = "replace" | "launch-existing"

// Maps the dialog response to an action. Anything that isn't an explicit
// Replace (Escape, Keep Existing) launches the existing install — the
// session must not continue from the DMG either way.
export const installDecisionForResponse = (
  prompt: Pick<ReturnType<typeof replacePrompt>, "replaceIndex">,
  response: number
): InstallDecision => (response === prompt.replaceIndex ? "replace" : "launch-existing")

// Dialog copy for a failed install COPY (the existing install, if any, is
// untouched — installBundle stages before it swaps): the app quits
// afterwards instead of running from the DMG, so the copy has to point at
// the manual path.
export const installFailedPrompt = ({
  bundleName,
  targetPath,
  reason
}: {
  bundleName: string
  targetPath: string | null
  reason?: string | null
}) => ({
  message: "Syrus could not be installed.",
  detail:
    `Copying ${bundleName}${targetPath ? ` to ${path.dirname(targetPath)}` : ""} failed. ` +
    "Drag Syrus into your Applications folder in Finder, then launch it from there." +
    (reason ? `\n\n(${reason})` : ""),
  buttons: ["Quit"] as const
})

// Dialog copy for a failed LAUNCH of an installed copy — either the one the
// user chose to keep, or the one that was just installed successfully. The
// install is in place; only the hand-over failed. The app quits afterwards,
// so the copy points at launching it manually.
export const launchFailedPrompt = ({
  targetPath,
  justInstalled,
  reason
}: {
  targetPath: string
  justInstalled: boolean
  reason?: string | null
}) => ({
  message: justInstalled
    ? "Syrus was installed but could not be opened."
    : "Syrus could not open the installed copy.",
  detail:
    (justInstalled
      ? `Syrus was installed to ${path.dirname(targetPath)} but couldn't be opened automatically. `
      : `Syrus couldn't open the installed copy at ${targetPath}. `) +
    "Launch it from Applications manually." +
    (reason ? `\n\n(${reason})` : ""),
  buttons: ["Quit"] as const
})

// Copies the bundle to the chosen target with ditto (preserves the code
// signature and bundle metadata a plain recursive copy would drop), strips
// the quarantine flag best-effort, and returns the installed path; throws if
// the copy cannot be produced.
//
// Staged swap, never destroy-then-copy: ditto lands in a sibling staging
// directory first (same volume, so the swap is a rename), the existing
// install is only moved aside once the full copy exists, and a failed final
// rename moves it back. A failure at any point leaves the previous install
// in place — the caller quits on failure, so "no runnable Syrus left" must
// be impossible when one existed before.
export const installBundle = async (bundlePath: string, target: string): Promise<string> => {
  await fs.mkdir(path.dirname(target), { recursive: true })

  const staging = `${target}.installing-${process.pid}`
  const previous = `${target}.previous-${process.pid}`
  await fs.rm(staging, { recursive: true, force: true })
  try {
    await execFileAsync("/usr/bin/ditto", [bundlePath, staging])
  } catch (error) {
    await fs.rm(staging, { recursive: true, force: true }).catch(() => {})
    throw error
  }

  let movedAside = false
  try {
    try {
      await fs.rename(target, previous)
      movedAside = true
    } catch {
      // No existing install at the target — nothing to move aside.
    }
    await fs.rename(staging, target)
  } catch (error) {
    if (movedAside) {
      await fs.rename(previous, target).catch(() => {})
    }
    await fs.rm(staging, { recursive: true, force: true }).catch(() => {})
    throw error
  }
  if (movedAside) {
    await fs.rm(previous, { recursive: true, force: true }).catch(() => {})
  }

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
