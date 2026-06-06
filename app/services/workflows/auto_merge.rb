module Workflows
  # Approved PR is ready to land.
  #
  #   prepare → retry_until(grader_fanout → grader_collect, repair: landing_fix) → push → auto_merge
  #
  # The final gate starts with graders on the exact PR branch Syrus
  # is about to merge, after any final rebase. landing_fix only runs
  # after a failed grade. push publishes fixes from any repair
  # iteration, and auto_merge re-fetches PR state immediately before
  # calling GitHub's merge API.
  class AutoMerge < Base
    steps :prepare,
          Workflows::RetryUntil.new(
            repair_first: false,
            repair: [ :landing_fix ],
            check: [ :grader_fanout, :grader_collect ]
          ),
          :push,
          :auto_merge

    def self.trigger_kind = "auto_merge"

    def self.steps_for(_job)
      [
        "prepare",
        Workflows::RetryUntil.new(
          max_iterations: AppSetting.grade_max_iterations,
          repair_first: false,
          repair: [ :landing_fix ],
          check: [ :grader_fanout, :grader_collect ]
        ),
        "push",
        "auto_merge"
      ]
    end

    def self.after_success(_workflow)
      LandingQueueProcessor.try_land!
    end

    def self.after_fail(workflow)
      job = workflow.job
      cleanup_unrepaired_workspace(workflow)
      return unless job&.landing?

      reason = workflow.artifact("failure_reason").presence || "auto_merge workflow failed"
      job.landing_failure_reason = reason.to_s.truncate(500)
      job.fail_landing! if job.may_fail_landing?
      job.save! if job.changed?
    end

    def self.cleanup_unrepaired_workspace(workflow)
      return if workflow.steps.where(kind: "landing_fix", state: "succeeded").exists?

      WorkflowWorkspace.cleanup_for(workflow)
    end
  end
end
