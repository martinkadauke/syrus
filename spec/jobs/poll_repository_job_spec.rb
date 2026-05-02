require "rails_helper"

RSpec.describe PollRepositoryJob do
  let(:user) { Factories.user(github_token: "ghp_test_token") }
  let(:repository) do
    Factories.repository(user: user, owner: "acme", name: "widgets", trigger_label: "syrus", polling_enabled: true)
  end

  describe "#perform", vcr: { cassette_name: "poll_repository_job/lists_issues" } do
    it "creates a Job for each issue that passes IngestPolicy and isn't dedup'd" do
      # Pre-seed: issue 46 already has a Job, must be dedup'd.
      Job.create!(user: user, repository: repository, issue_number: 46)

      expect {
        described_class.perform_now(repository.id)
      }.to change(Job, :count).by(1)

      created = Job.where(repository: repository).order(:created_at).last
      expect(created.issue_number).to eq(42)
      expect(created.state).to eq("open")
      expect(created.runs.first.state).to eq("queued")
    end

    it "dedups against any prior Job (open or closed) — prevents the duplicate-PR loop" do
      # Pre-seed: issue 46 has a Job whose initial run already succeeded
      # (PR is open and the thread is alive); issue 42 has a Job that
      # was closed. Either way the poller must not re-ingest. The old
      # code dedup'd only on active Job state and opened a fresh PR
      # every poll cycle.
      job_46 = Job.create!(user: user, repository: repository, issue_number: 46)
      job_46.runs.first.tap { |r| r.start!; r.succeed!; r.save! }

      job_42 = Job.create!(user: user, repository: repository, issue_number: 42)
      job_42.close_with_reason!("manual")

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

    it "skips archived repositories even with force: true" do
      repository.archive!
      expect {
        described_class.perform_now(repository.id, force: true)
      }.not_to change(Job, :count)
    end
  end
end
