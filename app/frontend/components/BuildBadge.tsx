import { desktopBuildSha } from "../lib/desktopShell"

// Tiny fixed corner note identifying exactly which builds are running —
// indispensable when juggling test DMGs and backend images. The backend
// revision comes from bootstrap (GIT_SHA baked into the image); the desktop
// app announces its own build via a User-Agent token. pointer-events-none:
// it must never eat a click.
export function BuildBadge({ revision }: { revision?: string | null }) {
  const appBuild = desktopBuildSha()
  const backend = revision && revision !== "dev" ? revision : null
  if (!appBuild && !backend) return null

  const parts = []
  if (appBuild) parts.push(`app ${appBuild}`)
  if (backend) parts.push(`backend ${backend}`)

  return (
    <div
      aria-hidden="true"
      className="pointer-events-none fixed bottom-1.5 right-2 z-40 select-none font-mono text-[10px] text-gray-400/80 dark:text-gray-600"
      data-testid="build-badge"
    >
      {parts.join(" · ")}
    </div>
  )
}
