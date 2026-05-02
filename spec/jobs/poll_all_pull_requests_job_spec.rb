require "rails_helper"

RSpec.describe PollAllPullRequestsJob do
  it "fans out to PollPullRequestJob only over open Jobs that have a PR" do
    user = Factories.user
    repo = Factories.repository(user: user)

    open_with_pr = Factories.job(repository: repo, issue_number: 1).tap do |j|
      j.update!(pr_number: 1)
    end
    Factories.job(repository: repo, issue_number: 2)  # open, no PR
    closed_with_pr = Factories.job(repository: repo, issue_number: 3).tap do |j|
      j.update!(pr_number: 3)
      j.close_with_reason!("manual")
    end

    expect {
      described_class.perform_now
    }.to have_enqueued_job(PollPullRequestJob).with(open_with_pr.id).once

    expect {
      described_class.perform_now
    }.not_to have_enqueued_job(PollPullRequestJob).with(closed_with_pr.id)
  end
end
