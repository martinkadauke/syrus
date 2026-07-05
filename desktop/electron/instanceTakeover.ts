// Single-instance takeover policy. Field lesson: an old Syrus running off a
// mounted DMG silently swallowed every newer launch for hours — the new
// instance lost the single-instance race, quit, and refocused the stale
// copy with zero indication anything was wrong. The launching instance now
// identifies itself via requestSingleInstanceLock's additionalData; the
// running instance compares and, when a DIFFERENT version or bundle
// launched, offers to quit and hand over instead of silently refocusing.
// Electron-free so the renderer test suite can exercise the decision.

export type InstanceIdentity = {
  version: string
  bundlePath: string
}

export type TakeoverDecision = "focus" | "offer"

export const decideOnSecondInstance = (
  own: InstanceIdentity,
  incoming: Partial<InstanceIdentity> | undefined
): TakeoverDecision => {
  // Old builds (or non-Syrus relaunch paths) send no identity — behave as
  // before and just focus.
  if (!incoming?.version || !incoming.bundlePath) {
    return "focus"
  }

  return incoming.version !== own.version || incoming.bundlePath !== own.bundlePath ? "offer" : "focus"
}

export const takeoverPrompt = (own: InstanceIdentity, incoming: InstanceIdentity) => ({
  message: "A different copy of Syrus was launched.",
  detail:
    `Running now: ${own.version} — ${own.bundlePath}\n` +
    `Just launched: ${incoming.version} — ${incoming.bundlePath}\n\n` +
    "Switch to the newly launched copy? This one will quit.",
  buttons: ["Switch to New Copy", "Keep Current"] as const,
  switchIndex: 0
})
