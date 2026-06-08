class PollMergeStateJob < ApplicationJob
  queue_as :default
  REBASE_MERGEABLE_STATES = %w[behind dirty].freeze

  limits_concurrency to: 1, key: ->(job_id) { "merge_state_poll:#{job_id}" }

  def perform(job_id)
    return if AppSetting.polling_paused?

    @job = Job.find_by(id: job_id)
    return unless @job

    # Cover both Syrus-authored PRs and external PRs owned by the
    # current user (the preempted-Job ingest path) — same scope as
    # the per-Job rebase worker uses.
    pr_number = @job.pr_number || @job.external_pr_number
    return unless pr_number
    return if @job.repository.archived?
    return if @job.workflows.active.exists?
    return if RebaseWorkflowSelector.active_for_stack?(@job)

    @client = GithubClient.for(repository: @job.repository, user: @job.user)
    @pr = @client.pull_request(@job.repository.slug, pr_number, bypass_cache: false)
    persist_mergeability(@pr)

    return if @pr.merged
    return if @pr.state == "closed"
    return unless we_control_head?(@pr)

    gate = AutoMergeGate.new(job: @job, client: @client, bypass_cache: true, pr: @pr).evaluate
    if gate.merge_ready?
      approve_for_landing
    elsif rebaseable_mergeable_state?
      dispatch_rebase
    end
  end

  private

  def persist_mergeability(pr)
    MergeabilityRecorder.record_github!(job: @job, pr: pr)
  end

  def mergeable_state
    @pr.respond_to?(:mergeable_state) ? @pr.mergeable_state : nil
  end

  def rebaseable_mergeable_state?
    REBASE_MERGEABLE_STATES.include?(mergeable_state)
  end

  def approve_for_landing
    return unless @job.may_approve?

    @job.approve_for_landing!
    audit("landing_queue: approved PR ##{@job.pr_number}; queued for landing")
    Rails.logger.info("[PollMergeStateJob] job #{@job.id} PR ##{@job.pr_number} approved and clean; queued for landing")
  end

  def dispatch_rebase
    if rebase_deferred_until_front_of_queue?
      audit("auto_merge: PR ##{@job.pr_number} is #{mergeable_state} but not near the front of the landing queue; deferring rebase until it advances")
      Rails.logger.info("[PollMergeStateJob] job #{@job.id} PR ##{@job.pr_number} #{mergeable_state} but far back in landing queue; skipping proactive rebase")
      return
    end

    if RebaseLoopGuard.noop_rebase_for?(job: @job, pr: @pr, client: @client)
      audit("auto_merge: #{mergeable_state} for same head/base after a no-op rebase; waiting for GitHub mergeability to refresh")
      Rails.logger.info("[PollMergeStateJob] job #{@job.id} PR ##{@job.pr_number} still #{mergeable_state} after no-op rebase; waiting")
      return
    end

    return if attempt_cap_reached?
    return if repo_rebase_concurrency_reached?

    workflow = RebaseWorkflowSelector.instantiate(job: @job, pr: @pr)
    audit("auto_merge: dispatching rebase #{workflow.slug} before merge")
    Rails.logger.info("[PollMergeStateJob] job #{@job.id} PR ##{@job.pr_number} needs rebase before merge-state evaluation")
    StepDispatcher.start_workflow(workflow)
  end

  # An approved Job that's behind/dirty but far back in the landing
  # queue doesn't need a proactive rebase — the base will move again
  # (re-dirtying it) before it reaches the front, and the auto_merge
  # preflight rebases the front Job inline when it lands. Only Jobs not
  # yet approved (still working toward mergeable so they can BE
  # approved) and the front-of-queue prefetch set get rebased here.
  def rebase_deferred_until_front_of_queue?
    @job.approved? && !LandingQueueProcessor.rebase_prefetch_candidate?(@job)
  end

  def we_control_head?(pr)
    pr.head&.repo&.full_name == pr.base&.repo&.full_name
  end

  def audit(message)
    run = @job.current_run
    return unless run

    JobLog.append!(run: run, chunk: message, kind: "system")
  end

  def attempt_cap_reached?
    RebaseAttemptGuard.cap_reached?(@job, pr: @pr)
  end

  def repo_rebase_concurrency_reached?
    active = RebaseWorkflowSelector.active_in_repository(@job.repository).count
    active >= PollRebaseJob::CONCURRENT_REBASES_PER_REPO
  end
end
