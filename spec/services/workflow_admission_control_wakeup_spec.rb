require "rails_helper"

RSpec.describe WorkflowAdmissionControlWakeup do
  include ActiveJob::TestHelper

  let(:user) { Factories.user }
  let(:repository) { Factories.repository(user: user) }

  it "enqueues deferred admission workflows and landing queue reprocessing" do
    job = Factories.job_record(user: user, repository: repository, state: "queued")
    workflow = Workflows::Initial.instantiate(job: job, agent_provider: "codex")
    workflow.update!(
      artifacts: {
        "start_blocked_reason" => StepDispatcher::ADMISSION_BLOCK_REASON,
        "start_blocked_details" => { "action" => "delay_until" }
      }
    )

    expect {
      described_class.call
    }.to have_enqueued_job(WorkflowPhaseAdmissionJob).with(workflow.id)
      .and have_enqueued_job(LandingQueueProcessorJob)
  end
end
