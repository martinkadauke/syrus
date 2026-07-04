import { describe, expect, it } from "vitest"
import { bundlePathFromExecPath, installedAppPath, shouldSelfInstall } from "../electron/selfInstall"

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
