class PollAllPullRequestsJob < ApplicationJob
  queue_as :default

  # Fan-out for the PR feedback loop — fires each open thread that has a
  # PR through PollPullRequestJob, which does the actual comment fetching
  # and follow-up Run dispatch.
  def perform
    Job.joins(:repository)
       .merge(Repository.active)
       .where(state: "open").where.not(pr_number: nil)
       .find_each do |job|
      PollPullRequestJob.perform_later(job.id)
    end
  end
end
