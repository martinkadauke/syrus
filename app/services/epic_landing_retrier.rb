# Re-triggers a failed Epic merge-train by re-approving the Epic's
# children that fell back to :implemented when the train failed
# (fail_landing clears approval). The explicit rebuild path can also
# recover failed members from the source train before re-approval.
# This is the bulk "Retry landing" affordance for an Epic — one action
# instead of re-approving N children individually. See
# docs/plans/landing-merge-train.md.
class EpicLandingRetrier
  def self.call(epic, by_user: nil) = new(epic, by_user: by_user).call
  def self.rebuild_merge_train!(epic, by_user: nil, source_train:)
    new(epic, by_user: by_user, source_train: source_train).rebuild_merge_train!
  end

  Result = Data.define(:reapproved_jobs, :recovered_jobs, :workflow) do
    def jobs = reapproved_jobs
    def any? = reapproved_jobs.any? || recovered_jobs.any? || workflow.present?
  end

  def initialize(epic, by_user: nil, source_train: nil)
    @epic = epic
    @by_user = by_user
    @source_train = source_train
  end

  def call
    result = reapprove_children

    # Kick the queue so the train dispatches without waiting for the
    # next recurring tick.
    LandingQueueProcessor.try_land! if result.reapproved_jobs.any?
    result.reapproved_jobs
  end

  def rebuild_merge_train!
    result = reapprove_children
    workflow = MergeTrainDispatcher.try_dispatch!(@epic, bypass_cooldown: true)

    Result.new(
      reapproved_jobs: result.reapproved_jobs,
      recovered_jobs: result.recovered_jobs,
      workflow: workflow
    )
  end

  private

  def reapprove_children
    reapproved = []
    recovered = []

    Job.transaction do
      recovered = recover_failed_train_members

      @epic.jobs.where(state: "implemented").find_each do |job|
        job.lock!
        next unless job.pr_number.present?
        next unless job.may_approve?

        job.approve!(via: "operator", by_user: @by_user)
        job.save!
        reapproved << job
      end
    end

    Result.new(reapproved_jobs: reapproved, recovered_jobs: recovered, workflow: nil)
  end

  def recover_failed_train_members
    return [] unless @source_train

    @source_train.members.includes(:job).filter_map do |member|
      job = member.job
      job.lock!
      next unless job.failed?
      next unless job.pr_number.present?

      job.assign_attributes(
        state: "implemented",
        approved_at: nil,
        approved_via: nil,
        approved_by_user_id: nil,
        approval_evidence: {},
        landing_failure_reason: nil
      )
      job.job_approvals.destroy_all
      job.save!
      job
    end
  end
end
