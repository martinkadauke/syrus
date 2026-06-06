class LandingFailureHandler
  INFRASTRUCTURE_BLOCKER_PATTERNS = [
    /\bENOSPC\b/i,
    /No space left on device/i,
    /Disk quota exceeded/i,
    /database or disk is full/i,
    /insufficient (?:disk|storage|space)/i,
    /not enough (?:disk|storage|space)/i
  ].freeze

  def self.call(...) = new(...).call

  def self.infrastructure_blocker?(reason)
    text = reason.to_s
    INFRASTRUCTURE_BLOCKER_PATTERNS.any? { |pattern| text.match?(pattern) }
  end

  def initialize(job:, reason:, run: nil)
    @job = job
    @reason = reason.to_s.presence || "auto_merge workflow failed"
    @run = run
  end

  def call
    return unless job&.landing?

    job.landing_failure_reason = reason.truncate(500)
    if infrastructure_blocker?
      pause_landing!
      job.defer_landing! if job.may_defer_landing?
    elsif rebase_cap_blocker?
      log_rebase_cap!
      job.defer_landing! if job.may_defer_landing?
    else
      job.fail_landing! if job.may_fail_landing?
    end
    job.save! if job.changed?
  end

  private

  attr_reader :job, :reason, :run

  def infrastructure_blocker?
    self.class.infrastructure_blocker?(reason)
  end

  def rebase_cap_blocker?
    reason.match?(/rebase cap reached/i)
  end

  def pause_landing!
    unless job.user.landing_paused?
      job.user.update!(landing_paused: true)
      log_pause!
    end
  end

  def log_pause!
    log_run = run || job.current_run
    return unless log_run

    JobLog.append!(
      run: log_run,
      kind: "system",
      chunk: "landing_queue: paused landing because auto-merge hit an infrastructure blocker; resume landing after clearing it (#{reason.truncate(180)})"
    )
  rescue StandardError => e
    Rails.logger.warn("[LandingFailureHandler] failed to log landing pause for Job ##{job.id}: #{e.class}: #{e.message}")
  end

  def log_rebase_cap!
    log_run = run || job.current_run
    return unless log_run

    JobLog.append!(
      run: log_run,
      kind: "system",
      chunk: "landing_queue: deferred landing because the rebase cap was reached; run a manual rebase or wait for the PR head/base to change before retrying"
    )
  rescue StandardError => e
    Rails.logger.warn("[LandingFailureHandler] failed to log rebase-cap blocker for Job ##{job.id}: #{e.class}: #{e.message}")
  end
end
