import { useT } from "../hooks/useT"
import { isDesktopTestChannel } from "../lib/desktopShell"

// An amber "TEST" pill shown only inside a side-by-side test build of the
// desktop app (detected via the SyrusDesktopChannel/test UA token). It makes a
// test build unmistakable in-app when a production release runs alongside it —
// the two windows are otherwise near-identical. Renders nothing in a plain
// browser, on the stable channel, or in an older shell without the token.
export function TestChannelBadge() {
  const { t } = useT("common")
  if (!isDesktopTestChannel()) {
    return null
  }

  return (
    <span
      data-testid="test-channel-badge"
      className="rounded px-1.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide bg-amber-50 text-amber-700 ring-1 ring-amber-200 dark:bg-amber-950/50 dark:text-amber-200 dark:ring-amber-800"
      title={t("test_channel_badge.tooltip")}
    >
      {t("test_channel_badge.label")}
    </span>
  )
}

// A compact amber corner dot — the same test-channel signal as TestChannelBadge
// for space-constrained spots (the floating mobile brand trigger) where the
// full pill won't fit. Renders nothing off the test channel. Callers place it
// inside a positioned parent; className overrides the corner offset.
export function TestChannelDot({ className }: { className?: string }) {
  const { t } = useT("common")
  if (!isDesktopTestChannel()) {
    return null
  }

  return (
    <span
      aria-label={t("test_channel_badge.label")}
      data-testid="test-channel-dot"
      title={t("test_channel_badge.tooltip")}
      className={
        className ??
        "absolute -right-0.5 -top-0.5 h-2.5 w-2.5 rounded-full bg-amber-500 ring-2 ring-white dark:ring-gray-950"
      }
    />
  )
}
