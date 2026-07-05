import { afterEach, describe, expect, it, vi } from "vitest"
import {
  bundlePathFromExecPath,
  installedAppPath,
  launchInstalledCopy,
  shouldSelfInstall
} from "../electron/selfInstall"

// selfInstall.ts promisifies execFile AT MODULE LOAD, so the async mock must
// be registered under the custom-promisify symbol for promisify() to pick it
// up. spawn is reached via a dynamic import, which resolves to the same
// mocked module. The path helpers above are pure, so the mock is inert for
// the pre-existing tests.
const { execFileAsyncMock, execFileMock, spawnMock, unrefMock } = vi.hoisted(() => {
  const execFileAsyncMock = vi.fn(async (..._args: unknown[]) => ({ stdout: "", stderr: "" }))
  const execFileMock = Object.assign(vi.fn(), {
    [Symbol.for("nodejs.util.promisify.custom")]: execFileAsyncMock
  })
  const unrefMock = vi.fn()
  const spawnMock = vi.fn((..._args: unknown[]) => ({ unref: unrefMock }))
  return { execFileAsyncMock, execFileMock, spawnMock, unrefMock }
})

// Vitest's node-builtin interop resolves through the default export, so the
// factory must provide both the default object and the named exports.
vi.mock("node:child_process", () => ({
  default: { execFile: execFileMock, spawn: spawnMock },
  execFile: execFileMock,
  spawn: spawnMock
}))

const home = "/Users/operator"
const base = { isPackaged: true, platform: "darwin" as NodeJS.Platform, homeDir: home }

describe("bundlePathFromExecPath", () => {
  it("walks from the binary to the .app bundle root", () => {
    expect(bundlePathFromExecPath("/Volumes/Syrus 0.1.0/Syrus.app/Contents/MacOS/Syrus")).toBe(
      "/Volumes/Syrus 0.1.0/Syrus.app"
    )
  })
})

describe("shouldSelfInstall", () => {
  it("installs when running from a mounted DMG", () => {
    expect(shouldSelfInstall({ ...base, bundlePath: "/Volumes/Syrus 0.1.0/Syrus.app" })).toBe(true)
  })

  it("installs when running from Downloads", () => {
    expect(shouldSelfInstall({ ...base, bundlePath: `${home}/Downloads/Syrus.app` })).toBe(true)
  })

  it("does not reinstall from /Applications or ~/Applications", () => {
    expect(shouldSelfInstall({ ...base, bundlePath: "/Applications/Syrus.app" })).toBe(false)
    expect(shouldSelfInstall({ ...base, bundlePath: `${home}/Applications/Syrus.app` })).toBe(false)
  })

  it("stays put for dev (unpackaged) builds and non-mac platforms", () => {
    expect(shouldSelfInstall({ ...base, isPackaged: false, bundlePath: "/Volumes/Syrus/Syrus.app" })).toBe(false)
    expect(
      shouldSelfInstall({ ...base, platform: "linux" as NodeJS.Platform, bundlePath: "/opt/Syrus.app" })
    ).toBe(false)
  })

  it("does not guess when the exec path is not inside a .app bundle", () => {
    expect(shouldSelfInstall({ ...base, bundlePath: "/Volumes/Syrus/weird-layout" })).toBe(false)
  })
})

describe("installedAppPath", () => {
  it("targets ~/Applications with the bundle's own name", () => {
    expect(installedAppPath(home, "/Volumes/Syrus 0.1.0/Syrus.app")).toBe(`${home}/Applications/Syrus.app`)
  })
})

describe("launchInstalledCopy", () => {
  const realPlatform = process.platform

  const setPlatform = (value: string) => {
    Object.defineProperty(process, "platform", { value, configurable: true })
  }

  afterEach(() => {
    Object.defineProperty(process, "platform", { value: realPlatform, configurable: true })
  })

  it("launches the installed .app through open(1) on macOS", async () => {
    setPlatform("darwin")

    await launchInstalledCopy(`${home}/Applications/Syrus.app`)

    expect(execFileAsyncMock).toHaveBeenCalledWith("/usr/bin/open", ["-n", `${home}/Applications/Syrus.app`])
    expect(spawnMock).not.toHaveBeenCalled()
  })

  it("spawns the installed exe detached on Windows and unrefs it", async () => {
    setPlatform("win32")
    const exe = "C:\\Users\\op\\AppData\\Local\\Programs\\Syrus\\Syrus.exe"

    await launchInstalledCopy(exe)

    // Detached + unref: the new copy must outlive this (about-to-quit)
    // process — the instance-takeover "Switch" path depends on it.
    expect(spawnMock).toHaveBeenCalledWith(exe, [], { detached: true, stdio: "ignore" })
    expect(unrefMock).toHaveBeenCalledTimes(1)
    expect(execFileAsyncMock).not.toHaveBeenCalled()
  })
})
