import { getJson } from "./client"

export type BootstrapPayload = {
  current_user: {
    id: number
    email_address: string
    name: string | null
    display_name: string
    admin: boolean
    scheduling_paused: boolean
    landing_paused: boolean
    agent_provider: "claude" | "codex"
    agent_max_turns: number
  }
  app: {
    revision: string
    revision_url: string | null
  }
  csrf_token: string
  feature_flags: {
    migrated_routes: string[]
  }
}

export function fetchBootstrap() {
  return getJson<BootstrapPayload>("/api/v1/app/bootstrap")
}
