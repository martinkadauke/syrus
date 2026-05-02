class PollRebaseJob < ApplicationJob
  queue_as :default

  # Cap how many rebase attempts we make per Job before giving up. The
  # second attempt usually succeeds when the first didn't (transient
  # CI noise, GitHub mergeable computation lag). Five rebases on the
  # same PR means the agent can't resolve the conflict mechanically —
  # bail and surface to the operator.
  REBASE_ATTEMPT_CAP = 5

  # One concurrent poll per Job — the same Job's rebase poll
  # shouldn't race itself or stack two rebase Runs at once.
  limits_concurrency to: 1, key: ->(job_id) { "rebase_poll:#{job_id}" }

  def perform(job_id)
    @job = Job.find_by(id: job_id)
    return unless @job

    pr_number = @job.pr_number || @job.external_pr_number
    return unless pr_number

    @client = GithubClient.for(@job.user)
    pr = @client.pull_request(@job.repository.slug, pr_number)

    return if pr.merged
    return if pr.state == "closed"

    # mergeable is true/false/null. Null = GitHub is still computing
    # mergeability after a recent push; try again next cycle. Only act
    # on a definitive false.
    return if pr.mergeable.nil?
    return if pr.mergeable                # mergeable; nothing to do

    return unless we_control_head?(pr)    # head from a fork → can't push
    return if pending_rebase?
    return if attempt_cap_reached?

    Rails.logger.info("[PollRebaseJob] job #{@job.id} PR ##{pr_number} is unmergeable; enqueueing rebase Run")
    @job.runs.create!(trigger_kind: "rebase")
  end

  private

  # Same-repo head means we have push access via the operator's
  # github_token. Forks would need maintainer-edits opt-in and a
  # different push URL; out of scope for v1.
  def we_control_head?(pr)
    pr.head&.repo&.full_name == pr.base&.repo&.full_name
  end

  def pending_rebase?
    @job.runs.where(trigger_kind: "rebase").active.exists?
  end

  def attempt_cap_reached?
    return false unless @job.runs.where(trigger_kind: "rebase").count >= REBASE_ATTEMPT_CAP
    Rails.logger.info("[PollRebaseJob] job #{@job.id} hit rebase cap (#{REBASE_ATTEMPT_CAP}); skipping")
    true
  end
end
