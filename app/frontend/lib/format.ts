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

// USD cost, always to 4 decimal places — agent costs are frequently fractions
// of a cent, so 2 decimals rounds distinct runs to the same "$0.00". Use this
// everywhere a dollar amount is shown.
export function formatCurrency(value: number): string {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 4,
    maximumFractionDigits: 4
  }).format(value)
}
