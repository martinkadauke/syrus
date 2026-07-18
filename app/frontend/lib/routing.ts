// Canonical route-prefix helper shared across the SPA. Prepends the active
// route prefix (e.g. "/app-shell") to an app-absolute path, leaving already-
// prefixed or non-absolute paths untouched. Feature route modules re-export
// this so existing local import paths keep working.
export function withRoutePrefix(path: string, prefix: string) {
  if (!prefix || path.startsWith(prefix)) return path
  if (!path.startsWith("/")) return path

  return `${prefix}${path}`
}
