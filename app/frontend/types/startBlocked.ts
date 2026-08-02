export type StartBlockedDetails = {
  kind?: string
  message?: string
  action?: string
  dependencies?: Array<{
    slug?: string
    job_id?: number
    branch_name?: string
    state?: string
  }>
}
