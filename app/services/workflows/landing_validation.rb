module Workflows
  # Feature-gated speculative prevalidation for the next same-repository Job in
  # the landing queue. It rebases the candidate PR onto the predicted tree left
  # by the current landing workflow, runs fast landing graders, and records a
  # LandingValidationCache artifact. It never pushes or merges; normal
  # auto_merge remains the serialized publication path.
  class LandingValidation < Base
    def self.trigger_kind = "landing_validation"

    def self.agentic? = false

    def self.queue_name = :merges

    def self.steps_for(job)
      chain = [
        "speculative_landing_build",
        "prepare",
        *grader_gate_steps
      ]
      without_skipped_prepare(job, chain)
    end

    def self.after_success(workflow)
      LandingQueueProcessor.try_land!(workflow.job)
    end

    def self.after_fail(workflow)
      LandingQueueProcessor.try_land!(workflow.job)
    end

    def self.after_cancel(workflow)
      LandingQueueProcessor.try_land!(workflow.job)
    end
  end
end
