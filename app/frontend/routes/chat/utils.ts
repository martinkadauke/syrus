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
