// Pure routing policy for navigations and window.open requests coming out of
// the web-container window. Kept free of Electron imports so it can be
// unit-tested from the renderer test suite.
//
// - "main": same-origin content stays in the web-container window.
// - "external": everything else goes to the user's default browser. The web
//   app can force this for same-origin URLs with the `syrus_external=1`
//   marker — used by flows that must run where the user has real logins,
//   e.g. the GitHub App manifest bounce page.
// - "deny": non-web protocols and unparseable URLs go nowhere.
//
// POST-carrying popups (form target=_blank) are NOT special-cased: a POST
// body cannot survive the hand-off to the external browser, so the web app
// must expose such flows as GET bounce pages instead of raw cross-origin
// form submissions.

export type WindowOpenAction = "main" | "external" | "deny"

export const decideWindowOpen = (rawUrl: string, serverOrigin: string): WindowOpenAction => {
  let target: URL
  try {
    target = new URL(rawUrl)
  } catch {
    return "deny"
  }

  if (!["http:", "https:"].includes(target.protocol)) {
    return "deny"
  }

  if (target.searchParams.get("syrus_external") === "1") {
    return "external"
  }

  return target.origin === serverOrigin ? "main" : "external"
}
