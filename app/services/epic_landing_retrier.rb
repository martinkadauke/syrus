# Re-triggers a failed Epic merge-train by re-approving the Epic's
# children that fell back to :implemented when the train failed
# (fail_landing clears approval). Once every open child is approved
# again the next LandingQueueProcessor tick dispatches a fresh train.
# This is the bulk "Retry landing" affordance for an Epic — one action
# instead of re-approving N children individually. See
# docs/plans/landing-merge-train.md.
class EpicLandingRetrier
  def self.call(epic, by_user: nil) = new(epic, by_user: by_user).call

  def initialize(epic, by_user: nil)
    @epic = epic
    @by_user = by_user
  end

  def call
    reapproved = []
    @epic.jobs.where(state: "implemented").find_each do |job|
      next unless job.pr_number.present?
      next unless job.may_approve?

      job.approve!(via: "operator", by_user: @by_user)
      job.save!
      reapproved << job
    end

    # Kick the queue so the train dispatches without waiting for the
    # next recurring tick.
    LandingQueueProcessor.try_land! if reapproved.any?
    reapproved
  end
end
