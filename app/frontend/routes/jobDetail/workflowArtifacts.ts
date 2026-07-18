// Workflow artifact/timestamp helpers extracted from JobDetail.tsx.
//
// Find the most recent workflow that recorded a coverage artifact, and the
// parsed created-at time for ordering. Pure over the job workflow + coverage
// types; lifted out of the 3k-line JobDetail.tsx.
import type { CoverageArtifact, JobWorkflow } from "../../api/jobs"

export function latestWorkflowCoverage(workflows: JobWorkflow[]): { workflowId: number; coverage: CoverageArtifact } | null {
  for (let i = workflows.length - 1; i >= 0; i--) {
    const artifacts = workflows[i].artifacts
    const cov = artifacts?.["coverage"] as CoverageArtifact | undefined
    if (cov) return { workflowId: workflows[i].id, coverage: cov }
  }
  return null
}

export function workflowCreatedAtTime(workflow: JobWorkflow) {
  if (!workflow.created_at) return 0
  const time = Date.parse(workflow.created_at)
  return Number.isNaN(time) ? 0 : time
}
