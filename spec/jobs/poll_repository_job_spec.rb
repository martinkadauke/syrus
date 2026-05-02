require "rails_helper"

RSpec.describe PollRepositoryJob do
  let(:user) { Factories.user(github_token: "ghp_test_token") }
  let(:repository) do
    Factories.repository(user: user, owner: "acme", name: "widgets", trigger_label: "syrus", polling_enabled: true)
  end

  describe "#perform", vcr: { cassette_name: "poll_repository_job/lists_issues" } do
    it "creates a Job for each issue that passes IngestPolicy and isn't dedup'd" do
      # Pre-seed: issue 46 already has a queued Job, must be dedup'd.
      Job.create!(user: user, repository: repository, issue_number: 46)

      expect {
        described_class.perform_now(repository.id)
      }.to change(Job, :count).by(1)

      created = Job.where(repository: repository).order(:created_at).last
      expect(created.issue_number).to eq(42)
      expect(created.state).to eq("queued")
    end

    it "dedups against terminal Jobs too — prevents the duplicate-PR loop" do
      # Pre-seed: issue 46 has a SUCCEEDED Job (PR already opened). The
      # old code only dedup'd against active state, so this poll would
      # have created a fresh Job → a fresh PR. With the fix, it doesn't.
      Job.create!(user: user, repository: repository, issue_number: 46, state: "succeeded")
      Job.create!(user: user, repository: repository, issue_number: 42, state: "failed")

      expect {
        described_class.perform_now(repository.id)
      }.not_to change(Job, :count)
    end

    it "skips a non-existent or polling-disabled repository" do
      repository.update!(polling_enabled: false)
      expect {
        described_class.perform_now(repository.id)
      }.not_to change(Job, :count)
    end

    it "force: true polls even when polling_enabled is false" do
      repository.update!(polling_enabled: false)
      expect {
        described_class.perform_now(repository.id, force: true)
      }.to change(Job, :count).by_at_least(1)
    end
  end
end
