import { BRAND_ICON_SRC } from "../lib/brandIcon"

export function SyrusBrand() {
  return (
    <span className="inline-flex items-center gap-2">
      <img alt="" aria-hidden="true" className="h-6 w-6 shrink-0 rounded" src={BRAND_ICON_SRC} />
      <span>Syrus</span>
    </span>
  )
}
