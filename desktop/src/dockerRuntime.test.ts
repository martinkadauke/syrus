import { afterEach, describe, expect, it, vi } from "vitest"
import { installWsl, wslReady } from "../electron/installer/dockerRuntime"

// dockerRuntime.ts promisifies execFile AT MODULE LOAD (`const execFileAsync =
// promisify(execFile)`), so mocking execFile's callback form alone is
// invisible to the module. promisify() prefers the function registered under
// the custom-promisify symbol, so the async mock is attached there.
const { execFileAsyncMock, execFileMock } = vi.hoisted(() => {
  const execFileAsyncMock = vi.fn(async (..._args: unknown[]) => ({ stdout: "", stderr: "" }))
  const execFileMock = Object.assign(vi.fn(), {
    [Symbol.for("nodejs.util.promisify.custom")]: execFileAsyncMock
  })
  return { execFileAsyncMock, execFileMock }
})

// Vitest's node-builtin interop resolves through the default export, so the
// factory must provide both the default object and the named export.
vi.mock("node:child_process", () => ({
  default: { execFile: execFileMock },
  execFile: execFileMock
}))

const realPlatform = process.platform

const setPlatform = (value: string) => {
  Object.defineProperty(process, "platform", { value, configurable: true })
}

afterEach(() => {
  Object.defineProperty(process, "platform", { value: realPlatform, configurable: true })
  execFileAsyncMock.mockReset()
})

describe("wslReady", () => {
  it("is trivially true on macOS without ever invoking wsl.exe", async () => {
    setPlatform("darwin")

    await expect(wslReady()).resolves.toBe(true)
    expect(execFileAsyncMock).not.toHaveBeenCalled()
  })

  it("reports true on Windows when `wsl.exe --status` succeeds", async () => {
    setPlatform("win32")
    execFileAsyncMock.mockResolvedValueOnce({ stdout: "Default Version: 2", stderr: "" })

    await expect(wslReady()).resolves.toBe(true)
    expect(execFileAsyncMock).toHaveBeenCalledWith(
      "wsl.exe",
      ["--status"],
      expect.objectContaining({ windowsHide: true })
    )
  })

  it("reports false on Windows when wsl.exe is missing or errors", async () => {
    setPlatform("win32")
    execFileAsyncMock.mockRejectedValueOnce(new Error("'wsl.exe' is not recognized"))

    await expect(wslReady()).resolves.toBe(false)
  })
})

describe("installWsl", () => {
  it("elevates a distribution-less `wsl --install` through PowerShell", async () => {
    setPlatform("win32")

    await installWsl()

    expect(execFileAsyncMock).toHaveBeenCalledTimes(1)
    const call = execFileAsyncMock.mock.calls[0]
    const [binary, args] = call as [string, string[], Record<string, unknown>]
    expect(binary).toBe("powershell.exe")
    const command = args[args.length - 1]
    // Docker Desktop brings its own distro, and feature install needs admin —
    // the command must skip the default distro and go through UAC.
    expect(command).toContain("'--install','--no-distribution'")
    expect(command).toContain("-Verb RunAs")
  })
})
