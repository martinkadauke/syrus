module Workflows
  # Approved PR is ready to land.
  #
  #   loop(landing_fix → grader_fanout → grader_collect) → push → auto_merge
  #
  # The landing_fix + grader loop runs on the exact PR branch Syrus
  # is about to merge, after any final rebase. push publishes fixes
  # from the loop, and auto_merge re-fetches PR state immediately
  # before calling GitHub's merge API.
  class AutoMerge < Base
    steps Workflows::Loop.new(steps: [ :landing_fix, :grader_fanout, :grader_collect ]),
          :push,
          :auto_merge

    def self.trigger_kind = "auto_merge"

    def self.steps_for(_job)
      [
        Workflows::Loop.new(
          max_iterations: AppSetting.grade_max_iterations,
          steps: [ :landing_fix, :grader_fanout, :grader_collect ]
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
      return unless job&.landing?

      reason = workflow.artifact("failure_reason").presence || "auto_merge workflow failed"
      job.landing_failure_reason = reason.to_s.truncate(500)
      job.fail_landing! if job.may_fail_landing?
      job.save! if job.changed?
    end
  end
end
