// Builds the Syrus CLI (a pure-Go binary — CGO_ENABLED=0, so no C toolchain
// needed) for macOS and Windows on both architectures and stages it into
// resources/cli/, which electron-builder bundles at <Resources>/cli with a
// per-platform filter (mac DMGs carry only the darwin binaries, NSIS only
// the windows ones — see electron-builder.yml). The app's Preferences offer
// a one-click install from there (see "install-syrus-cli" in
// electron/main.ts).
//
// Naming mirrors Electron's runtime identifiers so main.ts can derive the
// source as syrus-<process.platform>-<process.arch>[.exe]:
//   syrus-darwin-arm64, syrus-darwin-x64, syrus-win32-arm64.exe,
//   syrus-win32-x64.exe
//
// Skips with a notice when Go isn't available — the app then simply shows
// manual install guidance instead of the one-click button.
import { execFileSync } from "node:child_process"
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"

const desktopRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const cliRoot = path.resolve(desktopRoot, "..", "cli")
const stagingDir = path.join(desktopRoot, "resources", "cli")

fs.rmSync(stagingDir, { recursive: true, force: true })
fs.mkdirSync(stagingDir, { recursive: true })

let goBinary = "go"
try {
  execFileSync(goBinary, ["version"], { stdio: "ignore" })
} catch {
  const homebrewGo = "/opt/homebrew/bin/go"
  if (fs.existsSync(homebrewGo)) {
    goBinary = homebrewGo
  } else {
    console.log("stage-cli: Go not found — skipping CLI bundling (Preferences will show manual install guidance)")
    process.exit(0)
  }
}

const targets = [
  { goos: "darwin", platform: "darwin", suffix: "" },
  { goos: "windows", platform: "win32", suffix: ".exe" }
]

for (const target of targets) {
  for (const arch of ["arm64", "amd64"]) {
    const outName = `syrus-${target.platform}-${arch === "amd64" ? "x64" : arch}${target.suffix}`
    execFileSync(goBinary, ["build", "-trimpath", "-o", path.join(stagingDir, outName), "."], {
      cwd: cliRoot,
      env: { ...process.env, CGO_ENABLED: "0", GOOS: target.goos, GOARCH: arch },
      stdio: "inherit"
    })
    fs.chmodSync(path.join(stagingDir, outName), 0o755)
  }
}

console.log(`Staged Syrus CLI binaries into ${stagingDir}`)
