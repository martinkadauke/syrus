module JobsHelper
  STATE_STYLES = {
    "queued"    => "bg-gray-100 text-gray-700",
    "running"   => "bg-blue-100 text-blue-700",
    "succeeded" => "bg-green-100 text-green-700",
    "failed"    => "bg-red-100 text-red-700",
    "cancelled" => "bg-amber-100 text-amber-700",
    "open"      => "bg-emerald-100 text-emerald-700",
    "closed"    => "bg-gray-200 text-gray-800",
    "preempted" => "bg-violet-100 text-violet-700",
    "pending"   => "bg-gray-100 text-gray-700"
  }.freeze

  TRIGGER_STYLES = {
    "initial"     => "bg-purple-100 text-purple-700",
    "pr_comment"  => "bg-cyan-100 text-cyan-700",
    "ci_failure"  => "bg-red-100 text-red-700",
    "replay"      => "bg-amber-100 text-amber-700",
    "manual"      => "bg-gray-100 text-gray-700",
    "rebase"      => "bg-teal-100 text-teal-700"
  }.freeze

  def state_pill(state, classes: nil)
    style = STATE_STYLES[state.to_s] || "bg-gray-100 text-gray-700"
    tag.span(state, class: "inline-block px-2 py-0.5 rounded text-xs font-medium #{style} #{classes}")
  end

  def trigger_pill(trigger_kind)
    style = TRIGGER_STYLES[trigger_kind.to_s] || "bg-gray-100 text-gray-700"
    tag.span(trigger_kind, class: "inline-block px-2 py-0.5 rounded text-xs font-medium #{style}")
  end

  # The most useful one-word summary for a Job in a list view:
  # "preempted" beats "closed" when a Job was preempted by an external
  # PR — that's a more informative bucket than generic "closed."
  def job_summary_state(job)
    return "preempted" if job.closure_reason == "preempted"
    return "closed" if job.closed?
    job.current_run&.state || "pending"
  end

  def job_pr_url(job)
    return nil unless job.pr_number
    "https://github.com/#{job.repository.slug}/pull/#{job.pr_number}"
  end

  def external_pr_url(job)
    return nil unless job.external_pr_number
    "https://github.com/#{job.repository.slug}/pull/#{job.external_pr_number}"
  end

  def job_issue_url(job)
    "https://github.com/#{job.repository.slug}/issues/#{job.issue_number}"
  end
end
