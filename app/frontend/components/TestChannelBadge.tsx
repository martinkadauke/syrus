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
