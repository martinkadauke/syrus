// The ONE place the SPA reads "the desktop shell is updating the local
// backend right now". While a backend update runs the backend is
// DELIBERATELY unreachable for 1–3 minutes; every query against it fails.
// Surfaces that decide between "configured" and "not configured" from those
// checks (readiness banners, GitHub credential modals, setup empty states)
// gate on this hook so a failed check during the update never renders as
// absence — the field failure: a user was told their GitHub token was gone
// (it sat safely in the DB) while containers were being recreated.
//
// Fed by the same window.syrusShell bridge state ShellNotices renders
// (shell:state-changed), but held in a module-level store so any number of
// consumers share one bridge subscription. Plain browsers (and older shells
// without the backendUpdate member) never see a non-null value — the store
// stays inert at zero cost.

import { useSyncExternalStore } from "react"
import { syrusShellBridge, type SyrusBackendUpdate, type SyrusShellState } from "../lib/desktopShell"

let snapshot: SyrusBackendUpdate | null = null
let started = false
const listeners = new Set<() => void>()

function publish(next: SyrusBackendUpdate | null) {
  const changed = next?.phase !== snapshot?.phase || next?.percent !== snapshot?.percent
  if (!changed) return

  snapshot = next
  for (const listener of listeners) listener()
}

function start() {
  if (started) return
  started = true

  const bridge = syrusShellBridge()
  if (!bridge) return

  let sawEvent = false
  bridge.onStateChanged((state: SyrusShellState) => {
    sawEvent = true
    publish(state.backendUpdate ?? null)
  })
  // Deliberately never unsubscribed: the store lives as long as the page.
  void bridge
    .getState()
    .then((state) => {
      // A state-changed event that lands before this snapshot resolves is
      // fresher than the snapshot — never clobber it with stale data.
      if (!sawEvent) publish(state.backendUpdate ?? null)
    })
    .catch(() => {
      // A misbehaving bridge simply reports "not updating".
    })
}

function subscribe(listener: () => void) {
  start()
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

function getSnapshot() {
  return snapshot
}

// The in-flight backend update (phase + pull percent), or null when none.
export function useBackendUpdate(): SyrusBackendUpdate | null {
  return useSyncExternalStore(subscribe, getSnapshot)
}

// The boolean most gating surfaces want.
export function useBackendUpdating(): boolean {
  return useBackendUpdate() !== null
}

// Test seam: the store is module-global, so specs that install a fresh
// window.syrusShell mock must drop the previous subscription and snapshot.
export function resetBackendUpdateStoreForTests() {
  snapshot = null
  started = false
  listeners.clear()
}
