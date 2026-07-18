// Generic pure value/string utilities extracted from Chat.tsx.
//
// No React, no chat types — just coercion/normalization helpers used across
// the chat message/tool rendering. Lifting them into a leaf module lets the
// tool-rendering and message-transformation helpers move out of the 6k-line
// Chat.tsx without importing back from it.

export function stringValue(value: unknown) {
  return typeof value === "string" ? value : value == null ? "" : String(value)
}

export function stringArray(value: unknown) {
  return Array.isArray(value) ? value.map(stringValue).filter(Boolean) : []
}

export function contentRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : null
}

export function contentInput(content: unknown) {
  return contentRecord(contentRecord(content)?.input) || {}
}

export function firstLine(value: string) {
  return value.split(/\r?\n/, 1)[0].trim()
}

export function humanize(value: string) {
  const normalized = value.replace(/_id$/, "").replace(/_/g, " ").toLowerCase()
  return normalized ? normalized[0].toUpperCase() + normalized.slice(1) : ""
}

export function numericArg(value: string) {
  const match = value.trim().match(/^\d+$/)
  return match ? match[0] : null
}

export function errorAsError(error: unknown) {
  return error instanceof Error ? error : new Error(String(error))
}

export function formatCurrency(value: number, digits = 4) {
  return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", minimumFractionDigits: digits, maximumFractionDigits: digits }).format(value)
}

export function formatTokenCount(value: number) {
  if (value < 1000) return new Intl.NumberFormat("en-US").format(value)

  const thousands = value / 1000
  const compact = Number.isInteger(thousands) ? String(thousands) : thousands.toFixed(1).replace(/\.0$/, "")
  return `${compact}k`
}

export function parsePixelValue(value: string) {
  const parsed = Number.parseFloat(value)
  return Number.isFinite(parsed) ? parsed : 0
}

export function truncateSnapshotName(name: string) {
  return name.length > 40 ? `${name.slice(0, 39)}...` : name
}

export function providerLabel(provider: string) {
  if (provider === "claude") return "Claude"
  if (provider === "codex") return "Codex"
  return provider
}

export function startOfLocalDay(date: Date) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate())
}

export function sameLocalDay(left: Date, right: Date) {
  return left.getFullYear() === right.getFullYear() && left.getMonth() === right.getMonth() && left.getDate() === right.getDate()
}

export function dayDividerLabel(date: Date) {
  const today = startOfLocalDay(new Date())
  const candidate = startOfLocalDay(date)
  const dayDelta = Math.round((today.getTime() - candidate.getTime()) / (24 * 60 * 60 * 1000))

  if (dayDelta === 0) return "Today"
  if (dayDelta === 1) return "Yesterday"

  return date.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" })
}
