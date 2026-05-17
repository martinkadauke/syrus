require "rails_helper"

RSpec.describe ReapClassifierPendingJob do
  let(:repo) { Factories.repository }

  def pending_job(created_at:)
    job = Job.create!(
      user: repo.user,
      repository: repo,
      issue_number: rand(1..100_000),
      agent_provider: "claude"
    )
    # Force created_at — Job's before_validation can't reach back in
    # time. update_columns avoids touching updated_at and skips the
    # triaging_reason being normalized away from classifier_pending.
    job.update_columns(created_at: created_at, triaging_reason: "classifier_pending", state: "triaging")
    job
  end

  describe "#perform" do
    it "enqueues ClassifyIssueJob for each Job stuck past the threshold" do
      stuck = pending_job(created_at: 30.minutes.ago)

      expect(ClassifyIssueJob).to receive(:perform_later).with(stuck.id)

      described_class.perform_now
    end

    it "ignores Jobs created within the threshold window" do
      pending_job(created_at: 1.minute.ago)

      expect(ClassifyIssueJob).not_to receive(:perform_later)

      described_class.perform_now
    end

    it "ignores Jobs no longer in classifier_pending" do
      job = pending_job(created_at: 30.minutes.ago)
      job.update_columns(triaging_reason: "classifier_uncertain")

      expect(ClassifyIssueJob).not_to receive(:perform_later)

      described_class.perform_now
    end

    it "ignores Jobs that have left the triaging state" do
      job = pending_job(created_at: 30.minutes.ago)
      job.update_columns(state: "queued")

      expect(ClassifyIssueJob).not_to receive(:perform_later)

      described_class.perform_now
    end
  end
end
