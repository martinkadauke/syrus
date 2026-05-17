require "rails_helper"

RSpec.describe ClassifyIssueJob do
  let(:repo) { Factories.repository }
  let(:user) { repo.user }

  # Build a Job that's still in classifier_pending — we can't use
  # Factories.job because that auto-advances past triaging. Drop down
  # to AR directly and let the model's before_validation seed
  # triaging_reason="classifier_pending".
  def pending_job(**attrs)
    Job.create!({
      user: user,
      repository: repo,
      issue_number: 42,
      agent_provider: "claude"
    }.merge(attrs))
  end

  describe "#perform" do
    it "calls IngestionClassifier for an eligible Job" do
      allow(user).to receive(:agent_provider_configured?).with("claude").and_return(true)
      job = pending_job
      allow(Job).to receive(:find).with(job.id).and_return(job)
      allow(job).to receive(:user).and_return(user)

      expect(IngestionClassifier).to receive(:call).with(job: job)

      described_class.perform_now(job.id)
    end

    it "no-ops if the Job has already advanced past classifier_pending" do
      job = pending_job
      job.update_columns(state: "queued", triaging_reason: "classifier_pending")

      expect(IngestionClassifier).not_to receive(:call)

      described_class.perform_now(job.id)
    end

    it "no-ops if the Job's triaging_reason is no longer classifier_pending" do
      job = pending_job
      job.update_columns(triaging_reason: "classifier_uncertain")

      expect(IngestionClassifier).not_to receive(:call)

      described_class.perform_now(job.id)
    end

    it "no-ops if the user's agent provider isn't configured" do
      job = pending_job
      allow(Job).to receive(:find).with(job.id).and_return(job)
      allow(job).to receive(:user).and_return(user)
      allow(user).to receive(:agent_provider_configured?).with("claude").and_return(false)

      expect(IngestionClassifier).not_to receive(:call)

      described_class.perform_now(job.id)
    end

    it "discards (does not raise) if the Job has been deleted" do
      missing_id = 999_999
      expect { described_class.perform_now(missing_id) }.not_to raise_error
    end
  end
end
