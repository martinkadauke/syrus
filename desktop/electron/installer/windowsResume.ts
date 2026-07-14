import { execFile } from "node:child_process"
import { promisify } from "node:util"
import type { Channel } from "../channel.js"

const execFileAsync = promisify(execFile)

// Resume-after-reboot for the Windows onboarding flow. Docker Desktop's
// installer (and the one-click WSL 2 install) can force a Windows reboot in
// the middle of setup — the field failure: the wizard never came back and the
// user had to start over. HKCU RunOnce is Microsoft's blessed mechanism for
// exactly this ("transient conditions, such as to complete application
// setup"): the value fires once at that user's next logon and is deleted
// before the command runs. HKCU (not HKLM) because it needs no elevation and
// fires for the user who was mid-setup.
//
// The RunOnce entry only guarantees the app LAUNCHES after the reboot; the
// persisted onboardingResumeLocal flag (settings.ts) is what makes the wizard
// jump back into the local flow — so a plain manual relaunch resumes too, and
// a fired-but-crashed resume still works on the next start.
const RUN_ONCE_KEY = "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\RunOnce"

// The RunOnce value name is forked per channel so a test build mid-onboarding
// can't overwrite (register) or drop (uninstall) production's pending resume,
// and vice versa — every other namespaced resource is already channel-scoped.
// Both channels share one HKCU RunOnce key, so the VALUE name must differ.
export const runOnceValueName = (channel: Channel = "stable"): string =>
  channel === "test" ? "SyrusResumeSetupTest" : "SyrusResumeSetup"

// Exported for tests: the exact reg.exe argv. The command line must quote the
// exe path (profile paths contain spaces) and stay under RunOnce's 260-char
// data limit — Electron's execPath is well under it.
export const runOnceAddArgs = (execPath: string, channel: Channel = "stable"): string[] => [
  "add",
  RUN_ONCE_KEY,
  "/v",
  runOnceValueName(channel),
  "/t",
  "REG_SZ",
  "/d",
  `"${execPath}" --resume-setup`,
  "/f"
]

export const runOnceDeleteArgs = (channel: Channel = "stable"): string[] => [
  "delete",
  RUN_ONCE_KEY,
  "/v",
  runOnceValueName(channel),
  "/f"
]

// Best-effort by design: a failed registration must not block the download
// flow (the persisted flag still resumes on manual relaunch), and a failed
// delete leaves only a one-shot no-op launch behind.
export const registerRunOnceResume = async (
  channel: Channel = "stable",
  execPath: string = process.execPath
): Promise<void> => {
  if (process.platform !== "win32") {
    return
  }

  try {
    await execFileAsync("reg.exe", runOnceAddArgs(execPath, channel), { timeout: 10_000, windowsHide: true })
  } catch {
    // Persisted-flag fallback covers this.
  }
}

export const clearRunOnceResume = async (channel: Channel = "stable"): Promise<void> => {
  if (process.platform !== "win32") {
    return
  }

  try {
    await execFileAsync("reg.exe", runOnceDeleteArgs(channel), { timeout: 10_000, windowsHide: true })
  } catch {
    // Value absent (already fired or never registered) — fine.
  }
}
