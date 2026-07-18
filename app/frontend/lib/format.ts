// Shared formatting helpers (previously copied across routes).

// Human-readable byte size (B / KB / MB). Returns "unknown size" for a
// null/undefined value; 0 renders as "0 B". AdminOverview keeps its own
// TB/GB-capable variant.
export function formatBytes(value: number | null | undefined): string {
  if (value == null) return "unknown size"
  if (value < 1024) return `${value} B`
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KB`
  return `${(value / (1024 * 1024)).toFixed(1)} MB`
}

// Full date+time in the viewer's locale, "-" for a missing value. The canonical
// for what had been several byte-identical `null -> "-"; toLocaleString()` copies.
export function formatDateTime(value: string | null | undefined): string {
  if (!value) return "-"
  return new Date(value).toLocaleString()
}

// Full date+time in the viewer's locale, or null for a missing value (for
// callers that render their own fallback). Canonical for the identical
// `value ? toLocaleString() : null` copies.
export function formatDateTimeOrNull(value: string | null): string | null {
  return value ? new Date(value).toLocaleString() : null
}
