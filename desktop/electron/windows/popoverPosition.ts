// Pure positioning math for the tray popover. Kept free of Electron imports
// so the open-above flip and work-area clamps can be unit-tested; main.ts
// gathers the tray/window/screen state and applies the result.

export type Rect = { x: number; y: number; width: number; height: number }

export const computePopoverPosition = ({
  trayBounds,
  windowBounds,
  workArea,
  platform
}: {
  trayBounds: Rect
  windowBounds: { width: number; height: number }
  workArea: Rect
  platform: string
}): { x: number; y: number } => {
  let x = Math.round(trayBounds.x + trayBounds.width / 2 - windowBounds.width / 2)

  // Mac menu bar sits at the top → popover opens below the tray icon. The
  // Windows taskbar usually sits at the bottom → opening "below" would put
  // the popover off-screen, so open ABOVE when the tray is in the lower
  // half of the display.
  const trayInLowerHalf = trayBounds.y > workArea.y + workArea.height / 2
  let y = trayInLowerHalf
    ? Math.round(trayBounds.y - windowBounds.height - 4)
    : Math.round(trayBounds.y + trayBounds.height + (platform === "darwin" ? 0 : 4))

  // Clamp into the work area (multi-monitor edges, vertical taskbars).
  x = Math.min(Math.max(x, workArea.x), workArea.x + workArea.width - windowBounds.width)
  y = Math.min(Math.max(y, workArea.y), workArea.y + workArea.height - windowBounds.height)

  return { x, y }
}
