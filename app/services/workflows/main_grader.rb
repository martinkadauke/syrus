module Workflows
  # Runs .syrus.yml graders against the repository's default branch HEAD
  # to detect broken main before in-flight Jobs rebase onto it. Triggered
  # by MainGraderWorkflowJob when PollMainBranchHealthJob detects a new HEAD
  # SHA.
  #
  # Chain: prepare → grader_fanout → <per-grader steps> → grader_collect
  #
  # The chain has no retry loop: the result is binary — graders pass (healthy)
  # or fail (broken). after_success / after_fail update repository.grader_health
  # and call MainHealthChangedService when the health signal transitions.
  # The anchor Job is closed by the hook in both cases; it is excluded from
  # the operator UI (main_grader kind is filtered out of dashboard queries).
  class MainGrader < Base
    steps :prepare, :grader_fanout, :grader_collect

    def self.trigger_kind = "main_grader"

    def self.queue_name = :default

    def self.after_success(workflow)
      update_grader_health!(workflow, "healthy")
    end

    def self.after_fail(workflow)
      failed_names = failed_required_grader_names(workflow)

      if failed_names.any?
        update_grader_health!(workflow, "broken", failed_names)
      else
        Rails.logger.warn(
          "[Workflows::MainGrader] Workflow ##{workflow.id} failed before required graders reported failures; " \
          "leaving #{workflow.job.repository.slug} grader_health=#{workflow.job.repository.grader_health}"
        )
        close_anchor_job!(workflow)
      end
    end

    private_class_method def self.update_grader_health!(workflow, health, failed_names = nil)
      repository = workflow.job.repository
      previous_health = repository.main_health
      was_landing_paused = repository.landing_paused?
      repository.update!(grader_health: health)
      MainBranchHealthCheck.record_grader_workflow(
        repository: repository,
        sha: workflow.artifact("main_sha").to_s.presence || "unknown",
        grader_health: health,
        grader_failed_names: failed_names
      )
      repository.reload

      if repository.main_health != previous_health || (was_landing_paused && repository.grader_health_healthy? && !repository.ci_health_broken?)
        MainHealthChangedService.on_health_change!(repository)
      end

      close_anchor_job!(workflow)
    end

    private_class_method def self.failed_required_grader_names(workflow)
      workflow.steps
              .where(kind: "grader", state: "failed")
              .filter_map do |step|
                details = step.details || {}
                next unless details["required"]

                details["name"].presence || "unnamed"
              end
    end

    private_class_method def self.close_anchor_job!(workflow)
      StateTransition.with_source("system") do
        job = workflow.job
        job.close! if job.may_close?
        job.save!
      end
    end
  end
end
