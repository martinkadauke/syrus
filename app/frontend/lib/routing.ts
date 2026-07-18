// Canonical route-prefix helper shared across the SPA. Prepends the active
// route prefix (e.g. "/app-shell") to an app-absolute path, leaving already-
// prefixed or non-absolute paths untouched. Feature route modules re-export
// this so existing local import paths keep working.
export function withRoutePrefix(path: string, prefix: string) {
  if (!prefix || path.startsWith(prefix)) return path
  if (!path.startsWith("/")) return path

  return `${prefix}${path}`
}

// Derives the active route prefix from the current pathname. The app can be
// mounted under "/app-shell" (desktop shell) or at the root; this returns the
// prefix to prepend to app-absolute paths via withRoutePrefix.
export function routePrefix(pathname: string) {
  return pathname.startsWith("/app-shell") ? "/app-shell" : ""
}
