require "rails_helper"

RSpec.describe App::RetryState do
  describe ".for" do
    it "does not report an old failed workflow while a newer workflow is active" do
      job = Factories.job
      failed_workflow = job.latest_workflow
      failed_workflow.update!(
        state: "failed",
        artifacts: { "failure_classification" => "git_failure" },
        failure_count: 1,
        finished_at: 10.minutes.ago
      )
      job.initial_run.update_columns(state: "failed", finished_at: 10.minutes.ago)

      active_workflow = Workflow.create!(
        job: job,
        trigger_kind: "auto_merge",
        state: "running",
        started_at: 1.minute.ago
      )
      active_step = Step.create!(
        workflow: active_workflow,
        kind: "grader",
        position: 0,
        state: "running",
        started_at: 1.minute.ago
      )
      active_run = Run.create!(
        job: job,
        step: active_step,
        trigger_kind: "auto_merge",
        state: "succeeded",
        started_at: 1.minute.ago,
        finished_at: 30.seconds.ago
      )
      active_run.update_columns(state: "running", finished_at: nil)

      expect(described_class.for(job.reload)).to include(
        classification: nil,
        classification_label: "Unclassified",
        retryable: false,
        state_label: "No failure"
      )
    end

    it "does not report an old failed workflow after a newer workflow succeeds" do
      job = Factories.job
      job.latest_workflow.update!(
        state: "failed",
        artifacts: { "failure_classification" => "git_failure" },
        failure_count: 1,
        finished_at: 10.minutes.ago
      )
      job.initial_run.update_columns(state: "failed", finished_at: 10.minutes.ago)

      succeeded_workflow = Workflow.create!(
        job: job,
        trigger_kind: "rebase",
        state: "succeeded",
        started_at: 2.minutes.ago,
        finished_at: 1.minute.ago
      )
      succeeded_step = Step.create!(
        workflow: succeeded_workflow,
        kind: "auto_rebase",
        position: 0,
        state: "succeeded",
        started_at: 2.minutes.ago,
        finished_at: 1.minute.ago
      )
      Run.create!(
        job: job,
        step: succeeded_step,
        trigger_kind: "rebase",
        state: "succeeded",
        started_at: 2.minutes.ago,
        finished_at: 1.minute.ago
      )

      expect(described_class.for(job.reload)).to include(
        classification: nil,
        classification_label: "Unclassified",
        retryable: false,
        state_label: "No failure"
      )
    end

    it "reports the latest failed workflow when it is still the current attempt" do
      job = Factories.job
      job.latest_workflow.update!(
        state: "failed",
        artifacts: { "failure_classification" => "git_failure" },
        failure_count: 1,
        finished_at: 1.minute.ago
      )
      job.initial_run.update_columns(state: "failed", finished_at: 1.minute.ago)

      expect(described_class.for(job.reload)).to include(
        classification: "git_failure",
        classification_label: "Git failure",
        retryable: true,
        state_label: "Retryable failure"
      )
    end
  end
end
