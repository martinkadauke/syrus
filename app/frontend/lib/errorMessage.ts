import { ApiError } from "../api/client"

// Shared helper: extract a user-facing message from a caught error, falling
// back to the given default for non-ApiError failures. Previously copied
// verbatim into ~27 routes/components.
export function errorMessage(error: unknown, fallback: string): string {
  return error instanceof ApiError ? error.message : fallback
}
