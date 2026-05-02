require "rails_helper"

RSpec.describe PollAllRebasesJob do
  it "fans out to PollRebaseJob for every Job with a PR (Syrus or external), regardless of state" do
    syrus_pr   = Factories.job(pr_number: 7, branch_name: "syrus/issue-1-1")
    external   = Factories.job
    external.update!(state: "closed", closure_reason: "preempted",
                     external_pr_number: 99, finished_at: Time.current)
    closed_syr = Factories.job(pr_number: 8, branch_name: "syrus/issue-2-2")
    closed_syr.close_with_reason!("manual")
    no_pr      = Factories.job

    # No-PR Job is excluded (the SQL filter in PollAllRebasesJob).
    expect {
      described_class.perform_now
    }.to have_enqueued_job(PollRebaseJob).exactly(3).times
      .and have_enqueued_job(PollRebaseJob).with(syrus_pr.id)
      .and have_enqueued_job(PollRebaseJob).with(external.id)
      .and have_enqueued_job(PollRebaseJob).with(closed_syr.id)
    expect(no_pr.pr_number).to be_nil  # sanity
  end
end
