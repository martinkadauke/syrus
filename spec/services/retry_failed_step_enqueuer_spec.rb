require "rails_helper"

RSpec.describe RetryFailedStepEnqueuer do
  it "retries the latest failed step instead of an obsolete earlier failure" do
    job = Factories.job_record(state: "failed")
    workflow = Workflow.create!(job: job, trigger_kind: "initial")
    workflow.update_columns(state: "failed", started_at: 10.minutes.ago, finished_at: 1.minute.ago)

    old_failure = Step.create!(workflow: workflow, kind: "grader_collect", position: 7)
    later_success = Step.create!(workflow: workflow, kind: "summarize", position: 22)
    terminal_failure = Step.create!(workflow: workflow, kind: "pr_open", position: 23)
    old_failure.update_columns(state: "failed", started_at: 9.minutes.ago, finished_at: 8.minutes.ago)
    later_success.update_columns(state: "succeeded", started_at: 5.minutes.ago, finished_at: 4.minutes.ago)
    terminal_failure.update_columns(state: "failed", started_at: 2.minutes.ago, finished_at: 1.minute.ago)

    result = described_class.call(workflow: workflow)

    expect(result).to be_success
    expect(result.step).to eq(terminal_failure)
    expect(terminal_failure.reload).to be_queued
    expect(terminal_failure.runs.last).to eq(result.run)
    expect(old_failure.reload).to be_failed
    expect(old_failure.runs).to be_empty
  end
end
