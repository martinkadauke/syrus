module JobsHelper
  STATE_STYLES = {
    "queued"    => "bg-gray-100 text-gray-700",
    "running"   => "bg-blue-100 text-blue-700",
    "succeeded" => "bg-green-100 text-green-700",
    "failed"    => "bg-red-100 text-red-700",
    "cancelled" => "bg-amber-100 text-amber-700"
  }.freeze

  def job_state_pill(state)
    classes = STATE_STYLES[state.to_s] || "bg-gray-100 text-gray-700"
    tag.span(state, class: "inline-block px-2 py-0.5 rounded text-xs font-medium #{classes}")
  end

  def job_pr_url(job)
    return nil unless job.pr_number
    "https://github.com/#{job.repository.slug}/pull/#{job.pr_number}"
  end

  def job_issue_url(job)
    "https://github.com/#{job.repository.slug}/issues/#{job.issue_number}"
  end
end
