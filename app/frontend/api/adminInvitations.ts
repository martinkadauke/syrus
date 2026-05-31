import { deleteJson, getJson, postJson } from "./client"

export type AdminInvitation = {
  id: number
  email_address: string
  token: string
  share_url: string
  expires_at: string
  created_at: string
  invited_by_email_address: string
}

export type AdminInvitationsPayload = {
  invitations: AdminInvitation[]
  message?: string
}

export function fetchAdminInvitations() {
  return getJson<AdminInvitationsPayload>("/api/v1/app/admin/invitations")
}

export function createAdminInvitation(emailAddress: string) {
  return postJson<AdminInvitationsPayload>("/api/v1/app/admin/invitations", {
    invitation: { email_address: emailAddress }
  })
}

export function revokeAdminInvitation(id: number) {
  return deleteJson<AdminInvitationsPayload>(`/api/v1/app/admin/invitations/${id}`)
}
