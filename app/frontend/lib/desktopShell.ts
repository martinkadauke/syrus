// Helpers for running inside the Syrus desktop app's web container.
//
// The desktop shell intercepts window.open and either loads the URL in the
// main window (same-origin) or hands it to the OS default browser. Both
// paths make window.open return null — the same signal a browser popup
// blocker produces. openInNewTab tells the two apart so callers don't show
// "popup blocked" warnings for links that opened fine in the user's browser.

export function isDesktopShell(): boolean {
  return /\bSyrusDesktop\//.test(navigator.userAgent)
}

// Opens a URL in a new tab (or, in the desktop shell, wherever the shell
// routes it). Returns false only when a browser popup blocker genuinely
// swallowed the open. Deliberately not passing the `noopener` feature:
// per spec it forces window.open to return null, which is indistinguishable
// from a blocked popup — the opener is severed manually instead.
export function openInNewTab(url: string): boolean {
  const tab = window.open(url, "_blank")
  if (tab) {
    try {
      tab.opener = null
    } catch {
      // Cross-origin handle that refuses — nothing to do.
    }
    return true
  }

  return isDesktopShell()
}
