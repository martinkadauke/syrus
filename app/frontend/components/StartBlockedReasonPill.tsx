import { useT } from "../hooks/useT"
import type { StartBlockedDetails } from "../types/startBlocked"
import { TonePill } from "./StatusPill"

type StartBlockedReason =
  | "dependency_failed"
  | "stack_dependencies_not_ready"
  | "stack_fan_in_base_unavailable"
  | "job_not_ready_for_execution"
  | "main_branch_broken"
  | "urgent_job_active"

const TONES: Record<StartBlockedReason, "amber" | "red" | "gray"> = {
  dependency_failed: "red",
  stack_dependencies_not_ready: "amber",
  stack_fan_in_base_unavailable: "amber",
  job_not_ready_for_execution: "amber",
  main_branch_broken: "red",
  urgent_job_active: "gray"
}

export function StartBlockedReasonPill({ reason, details }: { reason: string; details?: StartBlockedDetails | null }) {
  const { t } = useT()
  const tone = TONES[reason as StartBlockedReason] ?? "amber"
  const title = startBlockedTitle(reason, details, t)

  return (
    <TonePill
      tone={tone}
      title={title}
    >
      {t(`common:start_blocked_reasons.${reason}`, { defaultValue: reason })}
    </TonePill>
  )
}

function startBlockedTitle(reason: string, details: StartBlockedDetails | null | undefined, t: ReturnType<typeof useT>["t"]) {
  const lines = [t(`common:start_blocked_reason_tooltips.${reason}`, { defaultValue: "" })].filter(Boolean)
  if (details?.message) lines.push(details.message)
  if (details?.dependencies?.length) {
    lines.push(`Dependencies: ${details.dependencies.map((dependency) => dependency.slug || (dependency.job_id ? `JOB-${dependency.job_id}` : null)).filter(Boolean).join(", ")}`)
  }
  if (details?.action) lines.push(details.action)
  return lines.join("\n")
}
