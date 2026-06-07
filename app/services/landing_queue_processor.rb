class LandingQueueProcessor
  MERGEABILITY_RECHECK_DELAY = 1.minute
  MERGEABILITY_WAIT_REASON = "waiting for GitHub mergeability".freeze

  Entry = Struct.new(:job, :position, :blocked_reason, :waiting_for, :waiting_for_jobs, keyword_init: true) do
    def eligible?
      blocked_reason.blank?
    end

    def job_id = job.id
  end

  def self.call = new.call

  def self.entries(scope = Job.all)
    new.entries(scope)
  end

  # Try to land a specific Job right now. Used by callers that have
  # just made a Job land-able and don't want to wait for the next
  # recurring tick — e.g. a Rebase workflow's success callback when
  # the Job is still approved. Returns the dispatched Workflow or
  # nil if the Job wasn't landable (not approved, blockage present,
  # landing already in progress for the same repository). With no Job,
  # kick the queue job immediately so it can choose the next eligible
  # approved Job.
  def self.try_land!(job = nil)
    return LandingQueueProcessorJob.perform_later unless job

    new.try_land!(job)
  end

  def try_land!(job)
    return if landing_in_progress_for_repository?(job.repository_id)
    return unless job.approved?
    return unless blockage_for(job)[:blocked_reason].blank?

    land(job)
  end

  def call
    start_ready_epic_sibling_jobs!

    occupied_repo_ids = Set.new(Job.landing.pluck(:repository_id))
    landed_workflows = []

    entries(Job.approved.includes(:user, :repository, :epic, :parent_job, dependencies: :depends_on_job)).each do |entry|
      next if occupied_repo_ids.include?(entry.job.repository_id)
      next unless entry.eligible?

      workflow = land(entry.job)
      next unless workflow

      landed_workflows << workflow
      occupied_repo_ids << entry.job.repository_id
    end

    landed_workflows.first
  end

  def entries(scope = Job.all)
    ordered_queue(scope).map.with_index(1) do |job, position|
      Entry.new(job: job, position: position, **blockage_for(job))
    end
  end

  private

  def ordered_queue(scope)
    chronological = scope.where(state: %w[ approved landing ])
                         .includes(:user, :repository, :epic, :parent_job, dependencies: :depends_on_job)
                         .order(Arel.sql("COALESCE(jobs.approved_at, jobs.updated_at) ASC"), :id)
                         .to_a

    dependency_order(chronological)
  end

  def dependency_order(jobs)
    by_id = jobs.index_by(&:id)
    original_index = jobs.each_with_index.to_h
    incoming = Hash.new { |hash, key| hash[key] = Set.new }
    outgoing = Hash.new { |hash, key| hash[key] = Set.new }

    jobs.each { |job| incoming[job.id] }
    jobs.each do |job|
      landing_queue_prerequisite_ids(job).each do |prerequisite_id|
        next unless by_id.key?(prerequisite_id)

        outgoing[prerequisite_id] << job.id
        incoming[job.id] << prerequisite_id
      end
    end

    ready = jobs.select { |job| incoming[job.id].empty? }
                .sort_by { |job| original_index.fetch(job) }
    ordered = []

    until ready.empty?
      job = ready.shift
      ordered << job

      outgoing[job.id].sort_by { |dependent_id| original_index.fetch(by_id.fetch(dependent_id)) }.each do |dependent_id|
        incoming[dependent_id].delete(job.id)
        ready << by_id.fetch(dependent_id) if incoming[dependent_id].empty?
      end
      ready.sort_by! { |ready_job| original_index.fetch(ready_job) }
    end

    ordered + jobs.reject { |job| ordered.include?(job) }
  end

  def landing_queue_prerequisite_ids(job)
    ids = []
    ids << job.parent_job_id if job.parent_job_id.present?
    job.dependencies.each do |dependency|
      next if job.dependencies_overridden_at.present?
      next if dependency.pending? || dependency.depends_on_job_id.blank?

      ids << dependency.depends_on_job_id
    end
    ids.uniq
  end

  def start_ready_epic_sibling_jobs!
    epic_ids = Job.approved.where.not(epic_id: nil).distinct.pluck(:epic_id)
    return if epic_ids.blank?

    Job.queued
       .where(epic_id: epic_ids)
       .includes(:repository, :workflows, dependencies: :depends_on_job)
       .find_each(&:start_pending_workflows_if_dependencies_satisfied!)
  end

  def land(job)
    workflow = nil
    landed = false
    Job.transaction do
      job.lock!
      raise ActiveRecord::Rollback if landing_in_progress_for_repository?(job.repository_id)
      raise ActiveRecord::Rollback unless job.approved?
      raise ActiveRecord::Rollback unless blockage_for(job)[:blocked_reason].blank?

      job.landing_failure_reason = nil
      job.start_landing!
      job.save!
      workflow = Workflows::AutoMerge.instantiate(job: job)
      audit(job, "landing_queue: dispatching auto-merge #{workflow.slug}")
      landed = true
    end
    return unless landed

    StepDispatcher.start_workflow(workflow)
    workflow
  end

  def landing_in_progress_for_repository?(repository_id)
    Job.landing.where(repository_id: repository_id).exists?
  end

  def blockage_for(job)
    return { blocked_reason: nil, waiting_for: nil, waiting_for_jobs: [] } if job.landing?
    return blocked("landing paused") if job.user.landing_paused?
    return blocked("repository archived") if job.repository.archived?
    # Don't burn a fail_landing cycle on a Job whose repo isn't set
    # up for auto-merge — that wipes the operator's approval without
    # surfacing the real misconfiguration. Keep the Job in :approved
    # with a clear blocked_reason; once the repo flips
    # auto_merge_enabled=true the queue picks it up immediately.
    return blocked("auto-merge not enabled for repository") unless job.repository.auto_merge_enabled?
    return blocked("missing pull request") if job.pr_number.blank?
    return blocked("active workflow") if job.workflows.active.exists?
    return blocked(MERGEABILITY_WAIT_REASON) if waiting_for_github_mergeability?(job)
    return blocked(RebaseLoopGuard::BLOCK_REASON) if RebaseLoopGuard.waiting_after_noop?(job)
    return blocked(RebaseAttemptGuard::BLOCK_REASON) if RebaseAttemptGuard.blocking_landing?(job)
    return blocked("waiting for Epic to release") if job.blocked_by_epic_before_execution?
    if job.epic
      unapproved_siblings = unapproved_epic_siblings(job)
      return blocked("waiting for epic siblings to be approved", waiting_for_jobs: unapproved_siblings) if unapproved_siblings.any?
    end

    parent = job.parent_job
    if parent && !merged?(parent)
      return blocked("waiting for ##{parent.issue_number || parent.id} to merge", parent)
    end

    dependency = job.dependencies_overridden_at.present? ? nil : unmerged_dependency(job)
    if dependency
      waiting = dependency.pending? ? dependency.unresolved_slug : dependency.depends_on_job
      return blocked("waiting for #{dependency_label(waiting)} to merge", waiting)
    end

    { blocked_reason: nil, waiting_for: nil, waiting_for_jobs: [] }
  end

  def blocked(reason, waiting_for = nil, waiting_for_jobs: [])
    { blocked_reason: reason, waiting_for: waiting_for, waiting_for_jobs: waiting_for_jobs }
  end

  def waiting_for_github_mergeability?(job)
    return false unless AutoMergeGate::TRANSIENT_MERGEABLE_STATES.include?(job.github_mergeable_state.to_s)
    return false if job.local_mergeable == false
    return false if job.mergeability_checked_at.blank?

    job.mergeability_checked_at > MERGEABILITY_RECHECK_DELAY.ago
  end

  def unapproved_epic_siblings(job)
    job.epic.jobs
       .where.not(id: job.id)
       .where.not(state: %w[ approved closed ])
       .order(:id)
       .to_a
  end

  def merged?(job)
    job.closed? && job.closure_reason == "pr_merged"
  end

  def unmerged_dependency(job)
    job.dependencies.includes(:depends_on_job).find do |dependency|
      dependency.pending? || !merged?(dependency.depends_on_job)
    end
  end

  def dependency_label(waiting)
    return waiting if waiting.is_a?(String)

    "##{waiting.issue_number || waiting.id}"
  end

  def audit(job, message)
    run = job.current_run
    return unless run

    JobLog.append!(run: run, chunk: message, kind: "system")
  end
end
