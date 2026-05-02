class PollPullRequestJob < ApplicationJob
  queue_as :default

  PR_COMMENT_FOLLOWUP_CAP = 5

  # One concurrent poll per Job — same Job's poll fanout shouldn't race
  # the watermark or stack two pr_comment Runs at once.
  limits_concurrency to: 1, key: ->(job_id, *) { "pr_poll:#{job_id}" }

  def perform(job_id)
    @job = Job.find_by(id: job_id)
    return unless @job&.open? && @job.pr_number.present?

    @client = GithubClient.for(@job.user)
    @slug = @job.repository.slug
    pr = @client.pull_request(@slug, @job.pr_number)

    return close_with("pr_merged") if pr.merged
    return close_with("pr_closed") if pr.state == "closed"
    return close_with("syrus_stop") if has_label?(pr, "syrus-stop")
    return close_with("pr_approved") if any_new_approval?

    return if cap_reached?
    return if pending_followup?

    new_comments = fetch_new_comments
    return if new_comments.empty?

    enqueue_followup_run(new_comments)
  end

  private

  def close_with(reason)
    Rails.logger.info("[PollPullRequestJob] closing job #{@job.id}: #{reason}")
    @job.runs.active.find_each do |r|
      r.cancel! if r.may_cancel?
      r.save!
    end
    @job.close_with_reason!(reason)
  end

  def has_label?(pr, name)
    Array(pr.labels).any? { |l| l.name == name }
  end

  def any_new_approval?
    reviews = @client.pr_reviews(@slug, @job.pr_number)
    cutoff = @job.last_seen_comment_at
    reviews.any? do |r|
      r.state == "APPROVED" && (cutoff.nil? || (r.submitted_at && r.submitted_at > cutoff))
    end
  end

  def cap_reached?
    return false unless @job.runs.where(trigger_kind: "pr_comment").count >= PR_COMMENT_FOLLOWUP_CAP
    Rails.logger.info("[PollPullRequestJob] job #{@job.id} hit pr_comment cap (#{PR_COMMENT_FOLLOWUP_CAP}); skipping")
    true
  end

  def pending_followup?
    @job.runs.where(trigger_kind: "pr_comment").active.exists?
  end

  def fetch_new_comments
    issue_comments = @client.pr_issue_comments(@slug, @job.pr_number, since: @job.last_seen_comment_at)
    review_comments = @client.pr_review_comments(@slug, @job.pr_number, since: @job.last_seen_comment_at)
    operator_login = @client.authenticated_login

    (issue_comments + review_comments)
      .reject { |c| c.user&.login == operator_login }
      .sort_by(&:created_at)
  end

  def enqueue_followup_run(new_comments)
    issue = @client.fetch_issue(@slug, @job.issue_number)
    prompt = PrFeedbackPrompt.new(issue: issue, comments: new_comments).to_s
    @job.runs.create!(trigger_kind: "pr_comment", prompt: prompt)

    latest = new_comments.map(&:created_at).max
    @job.update!(last_seen_comment_at: latest) if latest
  end
end
