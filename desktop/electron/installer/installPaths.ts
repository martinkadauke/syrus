import fs from "node:fs/promises"
import path from "node:path"
import { fileURLToPath } from "node:url"
import { app } from "electron"

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

// Packaged builds bundle install.sh + docker-compose.yml + compose.env.example
// (+ manifest.json) under <Resources>/backend via electron-builder
// extraResources; everything there is sealed by the code signature and must
// never be written to. In dev the repo root plays that role:
// desktop/dist-electron/installer/ -> ../../.. = the repo checkout.
export const installerAssetsDir = () => {
  if (app.isPackaged) {
    return path.join(process.resourcesPath, "backend")
  }

  return path.resolve(__dirname, "../../..")
}

export const installerScriptPath = () => path.join(installerAssetsDir(), "install.sh")

// Written by desktop/scripts/stage-backend-assets.mjs at build time: pins the
// backend image tag to this app release. Absent in dev — install.sh then
// falls back to ghcr.io/tkadauke/syrus-local:latest.
export type BackendManifest = {
  image?: string
  // The app's own build sha (git short sha at packaging time), announced as
  // a User-Agent token so the web UI's BuildBadge can show it.
  appBuild?: string
}

export const readBackendManifest = async (): Promise<BackendManifest | null> => {
  try {
    const contents = await fs.readFile(path.join(installerAssetsDir(), "manifest.json"), "utf8")
    const parsed = JSON.parse(contents) as BackendManifest
    return typeof parsed.image === "string" && parsed.image.trim() !== "" ? parsed : null
  } catch {
    return null
  }
}
