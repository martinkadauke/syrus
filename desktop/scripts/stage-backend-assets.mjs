#!/usr/bin/env node
// Stages the backend installer assets that electron-builder bundles into the
// app at <Resources>/backend (see extraResources in electron-builder.yml).
// The onboarding flow drives this exact install.sh; manifest.json pins the
// backend image tag to this app release, which is the contract read by
// desktop/electron/installer/installPaths.ts (readBackendManifest).
//
// Everything staged here ends up sealed by the code signature — install.sh
// writes its mutable state to --target-dir, never next to itself.
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"

const desktopRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const repoRoot = path.resolve(desktopRoot, "..")
const stagingDir = path.join(desktopRoot, "resources", "backend")

const pkg = JSON.parse(fs.readFileSync(path.join(desktopRoot, "package.json"), "utf8"))

fs.rmSync(stagingDir, { recursive: true, force: true })
fs.mkdirSync(stagingDir, { recursive: true })

for (const name of ["install.sh", "docker-compose.yml", "compose.env.example"]) {
  fs.copyFileSync(path.join(repoRoot, name), path.join(stagingDir, name))
}
fs.chmodSync(path.join(stagingDir, "install.sh"), 0o755)

// Release builds pin the image tag published by `bin/publish-image X.Y.Z`
// (the release workflow verifies the tag exists before building). Dev and
// prerelease versions fall back to :latest so unpublished builds still run.
const version = String(pkg.version ?? "")
const isReleaseVersion = /^\d+\.\d+\.\d+$/.test(version)
const image =
  process.env.SYRUS_BACKEND_IMAGE ??
  (isReleaseVersion ? `ghcr.io/tkadauke/syrus-local:${version}` : "ghcr.io/tkadauke/syrus-local:latest")

fs.writeFileSync(
  path.join(stagingDir, "manifest.json"),
  `${JSON.stringify({ image, appVersion: version }, null, 2)}\n`
)

console.log(`Staged backend assets into ${stagingDir} (image: ${image})`)
