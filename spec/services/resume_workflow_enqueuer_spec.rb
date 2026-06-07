require "rails_helper"

RSpec.describe ResumeWorkflowEnqueuer do
  include ActiveJob::TestHelper

  let(:job) { Factories.job(agent_provider: "codex") }
  let(:source_run) { job.initial_run }

  def fail_source_run!
    source_run.start!
    source_run.fail!
    source_run.save!
  end

  it "starts a resume workflow from a captured failed agent session" do
    fail_source_run!
    job.update!(state: "failed")
    ClaudeSession.create!(
      resumable: source_run,
      provider: "codex",
      session_id: "codex-thread",
      transcript_jsonl: "{}\n"
    )

    expect {
      result = described_class.call(job: job, source_run: source_run)
      expect(result).to be_success
      expect(result.run.parent_session_id).to eq("codex-thread")
      expect(result.workflow.trigger_kind).to eq("resume")
      expect(result.workflow.agent_provider).to eq("codex")
    }.to change { job.reload.workflows.where(trigger_kind: "resume").count }.by(1)
      .and have_enqueued_job(RunJob)

    expect(job.reload).to be_queued
  end

  it "rejects source runs without a captured session" do
    fail_source_run!

    result = described_class.call(job: job, source_run: source_run)

    expect(result).not_to be_success
    expect(result.error).to include("No agent session captured")
  end

  it "rejects active jobs" do
    fail_source_run!
    ClaudeSession.create!(
      resumable: source_run,
      provider: "codex",
      session_id: "codex-thread",
      transcript_jsonl: "{}\n"
    )
    job.runs.create!(trigger_kind: "manual", state: "running", started_at: Time.current)

    result = described_class.call(job: job, source_run: source_run)

    expect(result).not_to be_success
    expect(result.error).to include("already in progress")
  end
end
