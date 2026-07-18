require "stringio"

class MainHealthChangedService
  FIX_MAIN_TITLE = Job::MAIN_BRANCH_REPAIR_TITLE
  MAX_RECOVERY_RETRIES = 10
  MAX_OPEN_FAILED_FIX_JOBS = 3
  MAX_SUMMARY_ATTACHMENT_BYTES = 256.kilobytes
  MAX_CI_ATTACHMENT_BYTES = 4.megabytes
  MAX_GRADER_ATTACHMENT_BYTES = 12.megabytes
  BLOCKING_FIX_JOB_STATES = %w[needs_triage triaging queued running coding implemented approved landing].freeze

  def self.on_health_change!(repository)
    new(repository).on_health_change!
  end

  def self.recovered!(repository)
    new(repository).recovered!
  end

  def self.ensure_repair_job!(repository, force: false)
    new(repository).ensure_repair_job!(force: force)
  end

  def self.fix_main_job?(job)
    job.main_branch_repair?
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
      ensure_repair_job!
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

  def ensure_repair_job!(force: false)
    return unless @repository.main_branch_health_enabled?
    return unless @repository.main_branch_repair_enabled?
    return unless @repository.main_health_broken?
    return if blocking_fix_job

    unless force || repair_signals_ready?
      Rails.logger.info(
        "[MainHealthChangedService] #{@repository.slug} not spawning main repair job; " \
        "waiting for settled CI and grader signals for #{checked_sha}"
      )
      return
    end

    failed_count = open_failed_fix_jobs.count
    if failed_count >= MAX_OPEN_FAILED_FIX_JOBS
      Rails.logger.warn(
        "[MainHealthChangedService] #{@repository.slug} not spawning main repair job; " \
        "#{failed_count}/#{MAX_OPEN_FAILED_FIX_JOBS} failed repair jobs remain open"
      )
      return
    end

    spawn_fix_job!
  end

  def repair_status
    blocking = blocking_fix_job
    failed_jobs = recent_open_failed_fix_jobs.to_a
    failed_count = open_failed_fix_jobs.count
    eligible = @repository.main_branch_health_enabled? && @repository.main_branch_repair_enabled? && @repository.main_health_broken?
    below_failed_cap = failed_count < MAX_OPEN_FAILED_FIX_JOBS
    blocked_reason = if blocking
      blocking_fix_job_reason(blocking)
    elsif eligible && !repair_signals_ready?
      "waiting_for_health_signals"
    elsif eligible && !below_failed_cap
      "failed_open_cap"
    end
    can_request = eligible && blocking.blank? && below_failed_cap

    {
      enabled: @repository.main_branch_repair_enabled?,
      max_open_failed_jobs: MAX_OPEN_FAILED_FIX_JOBS,
      failed_open_jobs_count: failed_count,
      failed_jobs: failed_jobs,
      blocked_reason: blocked_reason,
      blocking_job: blocking,
      can_request: can_request,
      can_spawn: can_request && repair_signals_ready?
    }
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
    attempted_job_ids = {}

    Workflow
      .joins(:job)
      .where(jobs: { repository_id: @repository.id })
      .where.not(jobs: { state: "closed" })
      .where(state: "failed")
      .includes(:job)
      .order(id: :desc)
      .each do |workflow|
        break if retried >= MAX_RECOVERY_RETRIES
        next if attempted_job_ids[workflow.job_id]
        next unless recoverable_main_broken_workflow?(workflow)

        attempted_job_ids[workflow.job_id] = true
        result = RetryWorkflowEnqueuer.call(
          job: workflow.job,
          provider_validation: :none,
          automatic: true
        )
        retried += 1 if result.success?
      end
    retried
  end

  def recoverable_main_broken_workflow?(workflow)
    return false unless workflow.artifact("main_broken")
    return false if workflow.job.implemented? || workflow.job.approved? || workflow.job.landing?
    return false if newer_workflow_exists?(workflow)

    true
  end

  def newer_workflow_exists?(workflow)
    workflow
      .job
      .workflows
      .where("id > ?", workflow.id)
      .exists?
  end

  def spawn_fix_job!
    user = @repository.user
    return unless user

    job = user.jobs.create!(
      repository: @repository,
      kind: "direct",
      system_kind: Job::SYSTEM_KIND_MAIN_BRANCH_REPAIR,
      issue_number: nil,
      issue_title: FIX_MAIN_TITLE,
      issue_body: fix_job_prompt,
      agent_provider: @repository.effective_agent_provider,
      priority: "high"
    )
    attach_repair_context!(job)
    job.advance_after_triage! if job.may_advance_after_triage?
    job
  end

  def repair_jobs
    @repository.jobs
               .where(kind: "direct")
               .where(
                 "jobs.system_kind = :system_kind OR (jobs.system_kind IS NULL AND jobs.issue_title = :title)",
                 system_kind: Job::SYSTEM_KIND_MAIN_BRANCH_REPAIR,
                 title: FIX_MAIN_TITLE
               )
  end

  def open_failed_fix_jobs
    repair_jobs.where(state: "failed")
  end

  def recent_open_failed_fix_jobs
    open_failed_fix_jobs.order(updated_at: :desc, id: :desc).limit(MAX_OPEN_FAILED_FIX_JOBS)
  end

  def blocking_fix_job
    repair_jobs
      .where(state: BLOCKING_FIX_JOB_STATES)
      .order(updated_at: :desc, id: :desc)
      .first
  end

  def blocking_fix_job_reason(job)
    if job.needs_triage? || job.triaging? || job.queued? || job.running? || job.coding?
      "active"
    else
      "waiting"
    end
  end

  def fix_job_prompt
    sha = checked_sha
    prefix = repair_attachment_prefix(sha)

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
      "Diagnostic logs are attached to this Job and will be materialized in the workflow workspace.",
      "Start by reading tmp/attachments/#{prefix}-summary.md.",
      "Then inspect tmp/attachments/#{prefix}-ci.md and tmp/attachments/#{prefix}-graders.md if they are present.",
      "",
      "Use the attached context first. Identify the root cause from the default-branch CI and/or grader output, " \
      "then push a minimal fix to restore a green main. Do not expand scope beyond repairing main."
    ].join("\n")
  end

  def attach_repair_context!(job)
    sha = checked_sha
    checks = health_checks_for(sha)
    prefix = repair_attachment_prefix(sha)

    attach_text_file!(
      job,
      filename: "#{prefix}-summary.md",
      title: "Main branch repair summary",
      body: build_repair_summary(sha, checks),
      max_bytes: MAX_SUMMARY_ATTACHMENT_BYTES
    )

    ci_body = build_ci_log_attachment(sha, checks)
    if ci_body.present?
      attach_text_file!(
        job,
        filename: "#{prefix}-ci.md",
        title: "Main branch CI diagnostics",
        body: ci_body,
        max_bytes: MAX_CI_ATTACHMENT_BYTES
      )
    end

    grader_body = build_grader_log_attachment(sha, checks)
    if grader_body.present?
      attach_text_file!(
        job,
        filename: "#{prefix}-graders.md",
        title: "Main branch grader diagnostics",
        body: grader_body,
        max_bytes: MAX_GRADER_ATTACHMENT_BYTES
      )
    end
  rescue StandardError => e
    Rails.logger.warn(
      "[MainHealthChangedService] #{@repository.slug} failed to attach main repair context " \
      "to #{job.slug}: #{e.class}: #{e.message}"
    )
  end

  def attach_text_file!(job, filename:, title:, body:, max_bytes:)
    text = truncate_attachment_body(body, max_bytes)
    document = job.job_attachments.build(
      user: job.user,
      kind: "file",
      title: title,
      source_url: "main-health://#{job.id}/#{filename}",
      filename: filename,
      content_type: "text/markdown",
      byte_size: text.bytesize
    )
    document.file.attach(
      io: StringIO.new(text),
      filename: filename,
      content_type: "text/markdown",
      identify: false
    )
    document.save!
  end

  def build_repair_summary(sha, checks)
    lines = [
      "# Main branch repair context",
      "",
      "Repository: #{@repository.slug}",
      "Default branch: #{@repository.default_branch}",
      "Commit: #{sha}",
      "",
      "Current health:",
      "- CI: #{@repository.ci_health}",
      "- Graders: #{@repository.grader_health}",
      "",
      "Attached diagnostics:",
      "- #{repair_attachment_prefix(sha)}-ci.md: CI failure output and GitHub check links, when CI failed.",
      "- #{repair_attachment_prefix(sha)}-graders.md: Syrus grader workflow output, when graders reported a result.",
      "",
      "Recent health checks:"
    ]

    if checks.empty?
      lines << "- No detailed health-check rows were captured for this commit."
    else
      checks.each do |check|
        lines.concat(summary_lines_for(check))
      end
    end

    lines.join("\n")
  end

  def summary_lines_for(check)
    lines = [
      "- #{check.source} at #{check.checked_at.iso8601}: CI=#{check.ci_health || 'unknown'}, Graders=#{check.grader_health || 'unknown'}"
    ]

    failed_checks = Array(check.ci_failed_checks)
    if failed_checks.any?
      failed_checks.each do |failed_check|
        line = "  - CI failed: #{failed_check_name(failed_check)}"
        url = failed_check_url(failed_check)
        line += " (#{url})" if url
        lines << line
      end
    end

    names = Array(check.grader_failed_names).compact_blank
    lines << "  - Grader names: #{names.join(', ')}" if names.any?
    lines << "  - Workflow: #{workflow_label(check.workflow)}" if check.workflow
    lines
  end

  def build_ci_log_attachment(sha, checks)
    sections = checks.select { |check| check.ci_health == "broken" }.flat_map do |check|
      failed_checks = Array(check.ci_failed_checks)
      if failed_checks.empty?
        [ "## CI poll at #{check.checked_at.iso8601}\n\nCI failed, but GitHub did not provide failing check details." ]
      else
        failed_checks.map do |failed_check|
          ci_failed_check_section(check, failed_check)
        end
      end
    end

    return "" if sections.empty?

    [
      "# CI diagnostics for #{@repository.slug}@#{sha}",
      "",
      sections.join("\n\n")
    ].join("\n")
  end

  def ci_failed_check_section(check, failed_check)
    lines = [
      "## #{failed_check_name(failed_check)}",
      "",
      "- Checked at: #{check.checked_at.iso8601}"
    ]
    lines << "- Conclusion: #{failed_check_value(failed_check, 'conclusion')}" if failed_check_value(failed_check, "conclusion")
    lines << "- URL: #{failed_check_url(failed_check)}" if failed_check_url(failed_check)

    summary = failed_check_value(failed_check, "summary")
    if summary.present?
      lines.concat([ "", "### Summary", "", summary ])
    end

    log = failed_check_value(failed_check, "log")
    if log.present?
      lines.concat([ "", "### Log", "", "```text", log, "```" ])
    elsif failed_check_url(failed_check).present?
      lines.concat([ "", "No inline CI log text was available from GitHub's Check Run API. Use the URL above for full logs." ])
    end

    lines.join("\n")
  end

  def build_grader_log_attachment(sha, checks)
    sections = checks.select { |check| check.source == "grader_workflow" }.filter_map do |check|
      grader_check_section(check)
    end

    return "" if sections.empty?

    [
      "# Grader diagnostics for #{@repository.slug}@#{sha}",
      "",
      sections.join("\n\n")
    ].join("\n")
  end

  def grader_check_section(check)
    lines = [
      "## #{workflow_label(check.workflow)}",
      "",
      "- Checked at: #{check.checked_at.iso8601}",
      "- Grader health: #{check.grader_health || 'unknown'}"
    ]
    names = Array(check.grader_failed_names).compact_blank
    lines << "- Grader names: #{names.join(', ')}" if names.any?

    rendered = rendered_grader_output(check)
    if rendered.present?
      lines.concat([ "", rendered ])
    elsif check.workflow
      lines.concat([ "", "No structured grader iteration output was captured on this workflow." ])
    else
      lines.concat([ "", "No workflow was linked to this health-check row." ])
    end

    lines.join("\n")
  end

  def rendered_grader_output(check)
    workflow = check.workflow
    return "" unless workflow

    iterations = Array(workflow.artifact("iterations")).compact
    return "" if iterations.empty?

    Prompts::GradeFailureFeedback.new(
      iterations: iterations,
      intro: "The main-branch health graders captured these results:",
      include_guidance: false,
      include_git_safety: false
    ).to_s
  end

  def workflow_label(workflow)
    return "workflow unavailable" unless workflow

    workflow.respond_to?(:slug) ? workflow.slug : "workflow ##{workflow.id}"
  end

  def checked_sha
    @repository.last_health_checked_sha.to_s.presence || "unknown"
  end

  def repair_attachment_prefix(sha)
    "main-health-#{short_sha(sha)}"
  end

  def short_sha(sha)
    value = sha.to_s.presence || "unknown"
    value.length > 12 ? value[0, 12] : value
  end

  def health_checks_for(sha)
    return [] if sha == "unknown"

    MainBranchHealthCheck
      .where(repository: @repository, sha: sha)
      .includes(:workflow)
      .recent
      .limit(20)
      .to_a
  end

  def repair_signals_ready?
    sha = checked_sha
    return false if sha == "unknown"

    settled_ci_signal?(sha) && settled_grader_signal?(sha)
  end

  def settled_ci_signal?(sha)
    @repository.last_ci_evaluated_sha == sha &&
      @repository.ci_health.in?(MainBranchHealthCheck::SETTLED_CI_HEALTH) &&
      MainBranchHealthCheck.settled_ci_result_exists?(repository: @repository, sha: sha)
  end

  def settled_grader_signal?(sha)
    @repository.grader_health.in?(MainBranchHealthCheck::SETTLED_GRADER_HEALTH) &&
      MainBranchHealthCheck.settled_grader_result_exists?(repository: @repository, sha: sha)
  end

  def truncate_attachment_body(body, max_bytes)
    text = body.to_s
    return text if text.bytesize <= max_bytes

    notice = "\n\n... [truncated #{text.bytesize - max_bytes} bytes] ...\n"
    text.safe_byteslice(0, max_bytes - notice.bytesize) + notice
  end

  def failed_check_name(failed_check)
    failed_check_value(failed_check, "name") || "unknown check"
  end

  def failed_check_url(failed_check)
    failed_check_value(failed_check, "url") || failed_check_value(failed_check, "html_url")
  end

  def failed_check_value(failed_check, key)
    failed_check[key].presence || failed_check[key.to_sym].presence
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
