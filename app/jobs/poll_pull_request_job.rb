class PollPullRequestJob < ApplicationJob
  queue_as :default

  PR_COMMENT_FOLLOWUP_CAP = 5
  CI_FAILURE_CAP = 3

  # One concurrent poll per Job — same Job's poll fanout shouldn't race
  # the watermark or stack two pr_comment Runs at once.
  limits_concurrency to: 1, key: ->(job_id, *) { "pr_poll:#{job_id}" }

  def perform(job_id)
    @job = Job.find_by(id: job_id)
    return unless @job&.open? && @job.pr_number.present?

    @client = GithubClient.for(@job.user)
    @slug = @job.repository.slug
    @pr = @client.pull_request(@slug, @job.pr_number)

    return close_with("pr_merged") if @pr.merged
    return close_with("pr_closed") if @pr.state == "closed"
    return close_with("syrus_stop") if has_label?(@pr, "syrus-stop")
    return close_with("pr_approved") if any_new_approval?

    react_to_pr_comments
    react_to_ci_failures
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

  # ----- pr_comment branch ------------------------------------------------

  def react_to_pr_comments
    return if cap_reached?
    return if pending_followup?

    new_comments = fetch_new_comments
    return if new_comments.empty?

    enqueue_followup_run(new_comments)
  end

  # Counts Workflows now (each PrFeedback workflow has multiple
  # Runs — counting Runs would hit the cap after ~2 workflows). The
  # cap is "max pr_comment bursts on this Job".
  def cap_reached?
    return false unless @job.workflows.where(trigger_kind: "pr_comment").count >= PR_COMMENT_FOLLOWUP_CAP
    Rails.logger.info("[PollPullRequestJob] job #{@job.id} hit pr_comment cap (#{PR_COMMENT_FOLLOWUP_CAP}); skipping")
    true
  end

  def pending_followup?
    @job.workflows.active.where(trigger_kind: "pr_comment").exists?
  end

  # We don't filter by author. Syrus runs under the operator's PAT today
  # and doesn't post comments via the API — only pushes commits — so
  # there's no self-loop to prevent. The operator IS the reviewer; their
  # comments are exactly what we want to act on. When/if Syrus gets its
  # own bot identity (separate GitHub account or App), add a configurable
  # skip-by-login filter back here.
  def fetch_new_comments
    issue_comments = @client.pr_issue_comments(@slug, @job.pr_number, since: @job.last_seen_comment_at)
    review_comments = @client.pr_review_comments(@slug, @job.pr_number, since: @job.last_seen_comment_at)
    (issue_comments + review_comments).sort_by(&:created_at)
  end

  def enqueue_followup_run(new_comments)
    # Stash the comment payload on the workflow as a structured
    # artifact; Steps::Respond reads it at run time and composes
    # the Prompts::PrFeedback prompt itself. Polling job stays
    # ignorant of prompt internals.
    artifacts = {
      "pr_comments" => new_comments.map { |c| serialize_comment(c) }
    }
    workflow = Workflows::PrFeedback.instantiate(job: @job, artifacts: artifacts)
    StepDispatcher.start_workflow(workflow)

    latest = new_comments.map(&:created_at).max
    @job.update!(last_seen_comment_at: latest) if latest
  end

  # Octokit returns Sawyer::Resource objects; serialize to a plain
  # hash that round-trips through Workflow.artifacts (JSON column).
  def serialize_comment(c)
    {
      "author"     => c.user&.login,
      "body"       => c.body,
      "path"       => (c.respond_to?(:path) ? c.path : nil),
      "line"       => (c.respond_to?(:line) ? c.line : nil),
      "diff_hunk"  => (c.respond_to?(:diff_hunk) ? c.diff_hunk : nil),
      "created_at" => c.created_at&.iso8601
    }
  end

  # ----- ci_failure branch -----------------------------------------------

  def react_to_ci_failures
    head_sha = @pr.head&.sha
    return unless head_sha.present?
    return if @job.last_ci_handled_sha == head_sha   # already reacted to this commit
    return if ci_failure_cap_reached?
    return if pending_ci_failure_run?

    failed = @client.failed_check_runs_for(@slug, head_sha)
    return if failed.empty?

    enqueue_ci_failure_run(head_sha, failed)
  end

  def ci_failure_cap_reached?
    return false unless @job.workflows.where(trigger_kind: "ci_failure").count >= CI_FAILURE_CAP
    Rails.logger.info("[PollPullRequestJob] job #{@job.id} hit ci_failure cap (#{CI_FAILURE_CAP}); skipping")
    true
  end

  def pending_ci_failure_run?
    @job.workflows.active.where(trigger_kind: "ci_failure").exists?
  end

  def enqueue_ci_failure_run(head_sha, failed_checks)
    artifacts = {
      "head_sha"      => head_sha,
      "failed_checks" => failed_checks
    }
    workflow = Workflows::CiFailure.instantiate(job: @job, artifacts: artifacts)
    StepDispatcher.start_workflow(workflow)
    @job.update!(last_ci_handled_sha: head_sha)
    Rails.logger.info("[PollPullRequestJob] job #{@job.id}: enqueued CiFailure workflow ##{workflow.id} for #{head_sha[0..6]} (#{failed_checks.size} failing)")
  end
end
