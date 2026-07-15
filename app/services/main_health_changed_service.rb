class MainHealthChangedService
  FIX_MAIN_TITLE = "Fix broken main branch".freeze
  MAX_RECOVERY_RETRIES = 10

  def self.on_health_change!(repository)
    new(repository).on_health_change!
  end

  def self.recovered!(repository)
    new(repository).recovered!
  end

  def self.fix_main_job?(job)
    job.direct? && job.issue_title == FIX_MAIN_TITLE
  end

  def initialize(repository)
    @repository = repository
  end

  def on_health_change!
    unless @repository.main_branch_health_enabled?
      Rails.logger.info("[MainHealthChangedService] #{@repository.slug} main health disabled; ignoring health change")
      return
    end

    Rails.logger.warn(
      "[MainHealthChangedService] #{@repository.slug} main_health=#{@repository.main_health} " \
      "ci_health=#{@repository.ci_health} grader_health=#{@repository.grader_health}"
    )

    if @repository.main_health_broken?
      pause_landing!
      stamp_active_workflows!
      spawn_fix_job! if @repository.main_branch_repair_enabled?
      emit_notification!
    elsif @repository.main_health_inconclusive?
      pause_landing!
      emit_inconclusive_notification!
    elsif @repository.main_health == "healthy"
      self.class.recovered!(@repository)
    end
  end

  def recovered!
    Rails.logger.info(
      "[MainHealthChangedService] #{@repository.slug} main has recovered; resuming landing"
    )
    resume_landing!
    start_blocked_queued_workflows!
    retried_count = retry_held_jobs!
    emit_recovery_notification!(retried_count)
  end

  private

  def pause_landing!
    @repository.update!(landing_paused: true) unless @repository.landing_paused?
  end

  def resume_landing!
    @repository.update!(landing_paused: false) if @repository.landing_paused?
  end

  def stamp_active_workflows!
    Workflow.joins(:job)
            .where(jobs: { repository_id: @repository.id })
            .where(state: %w[queued running])
            .find_each do |workflow|
      workflow.set_artifact!("main_broken", true)
    end
  end

  def start_blocked_queued_workflows!
    # Queued workflows with no runs were blocked at the StepDispatcher gate
    # when main was broken. Call start_workflow again now that main is healthy.
    Workflow
      .joins(:job)
      .where(jobs: { repository_id: @repository.id })
      .where(state: "queued")
      .where.not(id: Workflow.joins(steps: :runs).select("workflows.id"))
      .find_each do |workflow|
        StepDispatcher.start_workflow(workflow)
      end
  end

  def retry_held_jobs!
    retried = 0
    Workflow
      .joins(:job)
      .where(jobs: { repository_id: @repository.id })
      .where.not(jobs: { state: "closed" })
      .where(state: "failed")
      .includes(:job)
      .each do |workflow|
        break if retried >= MAX_RECOVERY_RETRIES
        next unless workflow.artifact("main_broken")

        result = RetryWorkflowEnqueuer.call(
          job: workflow.job,
          provider_validation: :none,
          automatic: true
        )
        retried += 1 if result.success?
      end
    retried
  end

  def spawn_fix_job!
    return if open_fix_job_exists?

    user = @repository.user
    return unless user

    job = user.jobs.create!(
      repository: @repository,
      kind: "direct",
      issue_number: nil,
      issue_title: FIX_MAIN_TITLE,
      issue_body: fix_job_prompt,
      agent_provider: @repository.effective_agent_provider,
      priority: "high"
    )
    job.advance_after_triage! if job.may_advance_after_triage?
  end

  def open_fix_job_exists?
    @repository.jobs
               .where(kind: "direct", issue_title: FIX_MAIN_TITLE)
               .where.not(state: "closed")
               .exists?
  end

  def fix_job_prompt
    sha = @repository.last_health_checked_sha.presence || "unknown"

    [
      "Main branch health is broken for #{@repository.slug}.",
      "",
      "Default branch: #{@repository.default_branch}",
      "Commit: #{sha}",
      "",
      "Current health:",
      "- CI: #{@repository.ci_health}",
      "- Graders: #{@repository.grader_health}",
      "",
      "Known failure context:",
      *failure_context_lines(sha),
      "",
      "Use this context first. Identify the root cause from the default-branch CI and/or grader output, " \
      "then push a minimal fix to restore a green main. Do not expand scope beyond repairing main."
    ].join("\n")
  end

  def failure_context_lines(sha)
    return [ "- No checked commit is known yet." ] if sha == "unknown"

    lines = []
    MainBranchHealthCheck
      .where(repository: @repository, sha: sha)
      .recent
      .limit(5)
      .each do |check|
        lines.concat(ci_failure_lines(check))
        lines.concat(grader_failure_lines(check))
      end

    lines.uniq.presence || [ "- No detailed failure records have been captured yet." ]
  end

  def ci_failure_lines(check)
    return [] unless check.ci_health == "broken"

    failed_checks = Array(check.ci_failed_checks)
    return [ "- CI failed, but GitHub did not provide failing check details." ] if failed_checks.empty?

    failed_checks.map do |failed_check|
      name = failed_check["name"].presence || failed_check[:name].presence || "unknown check"
      url = failed_check["url"].presence ||
        failed_check[:url].presence ||
        failed_check["html_url"].presence ||
        failed_check[:html_url].presence
      if url
        "- CI failed: #{name} (#{url})"
      else
        "- CI failed: #{name}"
      end
    end
  end

  def grader_failure_lines(check)
    names = Array(check.grader_failed_names).compact_blank

    if check.grader_health == "broken"
      return [ "- Graders failed, but no grader names were captured." ] if names.empty?

      return [ "- Graders failed: #{names.join(', ')}" ]
    end

    if check.grader_health == "unknown" && names.any?
      return [ "- Grader check was interrupted while running: #{names.join(', ')}. This is not a conclusive grader failure." ]
    end

    if check.grader_health == "inconclusive" && names.any?
      return [ "- Grader check was inconclusive: #{names.join(', ')} timed out or did not produce a conclusive result." ]
    end

    []
  end

  def emit_notification!
    user = @repository.user
    return unless user

    signals = broken_signals
    sha = @repository.last_health_checked_sha.presence || "unknown"
    sha_short = sha.length > 8 ? sha[0, 8] : sha

    body = "Main branch broken on #{@repository.slug}: " \
           "#{signals.join(' and ')} failed at #{sha_short}."

    NotificationService.create_for(
      user: user,
      kind: "main_broken",
      body: body
    )
  end

  def emit_inconclusive_notification!
    user = @repository.user
    return unless user

    sha = @repository.last_health_checked_sha.presence || "unknown"
    sha_short = sha.length > 8 ? sha[0, 8] : sha

    NotificationService.create_for(
      user: user,
      kind: "main_inconclusive",
      body: "Main branch health is inconclusive on #{@repository.slug}: graders need operator review at #{sha_short}."
    )
  end

  def emit_recovery_notification!(retried_count)
    user = @repository.user
    return unless user

    body = "Main branch recovered on #{@repository.slug}."
    if retried_count > 0
      noun = retried_count == 1 ? "job" : "jobs"
      body += " #{retried_count} #{noun} queued for auto-retry."
    end

    NotificationService.create_for(
      user: user,
      kind: "main_recovered",
      body: body
    )
  end

  def broken_signals
    signals = []
    signals << "CI" if @repository.ci_health_broken?
    signals << "graders" if @repository.grader_health_broken?
    signals
  end
end
