require "rails_helper"

RSpec.describe WorkEngine::ReconcilerActivity do
  it "records issues, plans, executions, and a summary for a reconciler result" do
    job = Factories.job
    workflow = job.workflows.first
    run = job.initial_run
    issue = WorkEngine::Reconciler::Issue.new(
      kind: "queued_run_without_queue_claim",
      severity: "error",
      evidence: { solid_queue_state: "missing" },
      affected_ids: { job_ids: [ job.id ], workflow_ids: [ workflow.id ], run_ids: [ run.id ] },
      safe_to_auto_repair: true,
      recommended_repair_action: "reenqueue_run",
      explanation: "Run is queued but no active SolidQueue RunJob references it."
    )
    snapshot = instance_double(WorkEngine::Reconciler::Snapshot, as_json: {})
    result = WorkEngine::Reconciler::Result.new(
      "spec",
      Time.current,
      snapshot,
      [ issue ],
      [
        WorkEngine::RepairPlanner::Plan.new(
          issue_kind: issue.kind,
          action: "reenqueue_run",
          auto_executable: true,
          target_type: "Run",
          target_id: run.id,
          affected_ids: issue.affected_ids,
          execution_steps: [ "Run#reenqueue!" ],
          preconditions: {},
          reason: "The queued Run has no queue claim."
        )
      ],
      [
        WorkEngine::RepairExecutor::Execution.new(
          action: "reenqueue_run",
          target_type: "Run",
          target_id: run.id,
          status: "applied",
          message: "re-enqueued Run ##{run.id}"
        )
      ]
    )

    described_class.record_result!(
      source: "spec",
      job_id: job.id,
      execute_repairs: true,
      result: result
    )

    expect(WorkEngineReconcilerActivityEvent.order(:id).pluck(:event_type)).to eq(
      %w[issues_detected repair_planned repair_executed run_finished]
    )
    expect(WorkEngineReconcilerActivityEvent.find_by!(event_type: "issues_detected")).to have_attributes(
      job_id: job.id,
      workflow_id: workflow.id,
      run_id: run.id,
      issue_kind: issue.kind,
      repair_action: "reenqueue_run"
    )
    expect(WorkEngineReconcilerActivityEvent.find_by!(event_type: "run_finished").details).to include(
      "issues_count" => 1,
      "repair_executions_count" => 1
    )
  end
end
