import { describe, expect, it } from "vitest"
import { runOnceAddArgs, runOnceDeleteArgs, runOnceValueName } from "../electron/installer/windowsResume"

// The reboot-resume contract: Docker Desktop / WSL installs can force a
// Windows reboot mid-onboarding, and HKCU RunOnce is what relaunches Syrus at
// the next logon so setup continues instead of stranding the user (the
// persisted onboardingResumeLocal flag then jumps back into the local flow).
describe("windowsResume RunOnce registration", () => {
  it("registers under HKCU RunOnce with a quoted exe path", () => {
    // Profile paths contain spaces (C:\Users\First Last\...) — an unquoted
    // command line would truncate at the first space and launch nothing.
    const args = runOnceAddArgs("C:\\Users\\First Last\\AppData\\Local\\Programs\\Syrus\\Syrus.exe")

    expect(args[0]).toBe("add")
    expect(args[1]).toBe("HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\RunOnce")
    expect(args).toContain("SyrusResumeSetup")
    expect(args).toContain("REG_SZ")
    expect(args).toContain('"C:\\Users\\First Last\\AppData\\Local\\Programs\\Syrus\\Syrus.exe" --resume-setup')
    expect(args[args.length - 1]).toBe("/f")
  })

  it("stays under RunOnce's 260-char command-line limit for realistic paths", () => {
    const args = runOnceAddArgs("C:\\Users\\Somebody\\AppData\\Local\\Programs\\Syrus\\Syrus.exe")
    const commandLine = args[args.indexOf("/d") + 1]

    expect(commandLine.length).toBeLessThan(260)
  })

  it("deletes the same value it registered", () => {
    const args = runOnceDeleteArgs()

    expect(args[0]).toBe("delete")
    expect(args[1]).toBe("HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\RunOnce")
    expect(args).toContain("SyrusResumeSetup")
    expect(args[args.length - 1]).toBe("/f")
  })

  // The two channels share one HKCU RunOnce KEY, so the VALUE name must fork —
  // otherwise a test build mid-onboarding overwrites (or, on uninstall, drops)
  // production's pending resume hook, and vice versa.
  it("forks the RunOnce value name by channel", () => {
    expect(runOnceValueName("stable")).toBe("SyrusResumeSetup")
    expect(runOnceValueName("test")).toBe("SyrusResumeSetupTest")
    // Defaults to stable so an un-threaded caller never touches the test value.
    expect(runOnceValueName()).toBe("SyrusResumeSetup")
    expect(runOnceValueName("test")).not.toBe(runOnceValueName("stable"))
  })

  it("registers and deletes the channel-specific value on the test channel", () => {
    const addArgs = runOnceAddArgs("C:\\Users\\Ada\\AppData\\Local\\Syrus Test\\Syrus Test.exe", "test")
    expect(addArgs).toContain("SyrusResumeSetupTest")
    expect(addArgs).not.toContain("SyrusResumeSetup") // exact-match: the stable name is not present
    expect(addArgs).toContain('"C:\\Users\\Ada\\AppData\\Local\\Syrus Test\\Syrus Test.exe" --resume-setup')

    const deleteArgs = runOnceDeleteArgs("test")
    expect(deleteArgs).toContain("SyrusResumeSetupTest")
    expect(deleteArgs).not.toContain("SyrusResumeSetup")
  })
})
