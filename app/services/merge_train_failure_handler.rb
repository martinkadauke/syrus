# Reverts an Epic merge-train's member Jobs when the train workflow
# fails or is cancelled, reusing the per-PR landing-failure semantics so
# transient blockers auto-retry and genuine failures require operator
# re-approval. See docs/plans/landing-merge-train.md.
class MergeTrainFailureHandler
  def self.call(workflow:, cancelled: false) = new(workflow: workflow, cancelled: cancelled).call

  def initialize(workflow:, cancelled: false)
    @workflow = workflow
    @cancelled = cancelled
  end

  def call
    train = merge_train
    return unless train

    reason = failure_reason
    unless train.terminal?
      train.update!(state: @cancelled ? "cancelled" : "failed", failure_reason: reason.truncate(500), finished_at: Time.current)
    end

    train.members.each do |member|
      next if member.state == "merged"

      job = member.job
      # LandingFailureHandler classifies the reason: transient/infra
      # blockers defer_landing (stay approved, auto-retry), genuine
      # failures fail_landing (-> implemented, approval cleared, requires
      # operator re-approval).
      LandingFailureHandler.call(job: job, reason: reason) if job.landing?
      member.update!(state: "failed", reason: reason.truncate(500))
    end
  end

  private

  def failure_reason
    (@workflow.failure_reason.presence ||
      @workflow.artifact("failure_reason").presence ||
      (@cancelled ? "merge_train cancelled" : "merge_train failed")).to_s
  end

  def merge_train
    id = @workflow.artifact("merge_train_id")
    return if id.blank?

    MergeTrain.find_by(id: id)
  end
end
