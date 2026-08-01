export type ProviderAvailability = {
  provider: string
  label: string
  model: string | null
  state: "available" | "exhausted" | "open" | "rate_limited" | string
  open: boolean
  usage_exhausted: boolean
  retry_after: string | null
  reason: string | null
  message: string
  usage?: {
    status?: string | null
    observed_at?: string | null
    remaining_percent?: number | null
    windows?: {
      five_hour?: ProviderUsageWindow
      weekly?: ProviderUsageWindow
    }
  } | null
} | null

export type ProviderUsageWindow = {
  label: string
  remaining_percent?: number | null
  used_percent?: number | null
  reset_at?: string | null
}
