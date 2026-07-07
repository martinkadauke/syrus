import { desktopCapturer, session } from "electron"

// getDisplayMedia support for the walkthrough recorder. In Electron the call
// REJECTS unless a display-media handler is registered — the web app's
// "Record a walkthrough" would silently fail in the desktop shell without
// this, while working fine in a plain Chrome tab.
//
// macOS: defer to the native SCContentSharingPicker (useSystemPicker,
// Electron 33+) — the same picker Chrome/Meet users see, and it OWNS the
// Screen Recording permission flow, so no TCC preflight/relaunch dance is
// needed. Windows/Linux: no OS picker exists; capture the primary screen —
// a walkthrough is "show the app I'm testing", and full-screen capture is
// the least surprising default. (A per-window source picker is a natural
// follow-up if users ask.)
export const registerScreenCaptureHandler = () => {
  session.defaultSession.setDisplayMediaRequestHandler(
    (_request, callback) => {
      desktopCapturer
        .getSources({ types: ["screen"] })
        .then((sources) => {
          if (sources.length === 0) {
            callback({})
            return
          }
          callback({ video: sources[0] })
        })
        .catch(() => callback({}))
    },
    { useSystemPicker: true }
  )
}
