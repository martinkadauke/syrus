import { getJson } from "./client"

export type AdminPluginPage = {
  id: string
  label: string
  path: string
  paths: string[]
  order: number
}

export type AdminPluginPagesPayload = {
  pages: AdminPluginPage[]
}

export function fetchAdminPluginPages() {
  return getJson<AdminPluginPagesPayload>("/api/v1/app/admin/plugin_pages")
}
