export type AdminSmartFolder = {
  id: number
  name: string
  kind: string
  subject_type: string
  visibility: string
  count: number
  active: boolean
  path: string
}

export type AdminSmartFolderPayload = {
  active_smart_folder_id: number | null
  smart_folders: AdminSmartFolder[]
}
