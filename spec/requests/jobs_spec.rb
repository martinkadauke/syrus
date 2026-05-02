require "rails_helper"

RSpec.describe "Jobs", type: :request do
  let(:user)  { Factories.user }
  let(:other) { Factories.user }
  let(:repository) { Factories.repository(user: user, owner: "acme", name: "widgets") }
  let(:job) { Factories.job(repository: repository, issue_number: 42) }

  describe "GET /jobs/:id" do
    it "requires authentication" do
      get job_path(job)
      expect(response).to redirect_to(new_session_path)
    end

    context "signed in" do
      before { sign_in_as(user) }

      it "shows the job with state, repo, transcript, diff" do
        JobLog.create!(job: job, sequence: 0, chunk: "hello transcript")
        job.update!(agent_diff: "diff --git a/foo b/foo\n+bar")

        get job_path(job)
        expect(response).to be_successful
        expect(response.body).to include("acme/widgets")
        expect(response.body).to include("#42")
        expect(response.body).to include("hello transcript")
        expect(response.body).to include("diff --git")
      end

      it "404s for another user's job" do
        foreign_repo = Factories.repository(user: other)
        foreign_job = Factories.job(repository: foreign_repo, issue_number: 1)
        get job_path(foreign_job)
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /jobs/:id/replay" do
    before { sign_in_as(user) }

    it "creates a new Job with the same repo + issue and enqueues RunJob" do
      job
      expect {
        post replay_job_path(job)
      }.to change(Job, :count).by(1)
        .and have_enqueued_job(RunJob)

      new_job = Job.where(repository_id: repository.id, issue_number: 42).order(:created_at).last
      expect(new_job.id).not_to eq(job.id)
      expect(response).to redirect_to(job_path(new_job))
    end
  end

  describe "POST /jobs/:id/cancel" do
    before { sign_in_as(user) }

    it "transitions a queued job to cancelled" do
      post cancel_job_path(job)
      expect(job.reload.state).to eq("cancelled")
      expect(response).to redirect_to(job_path(job))
    end

    it "transitions a running job to cancelled" do
      job.start!
      post cancel_job_path(job)
      expect(job.reload.state).to eq("cancelled")
    end

    it "refuses to cancel a terminal job" do
      job.start!
      job.succeed!
      post cancel_job_path(job)
      expect(job.reload.state).to eq("succeeded")
      expect(flash[:alert]).to match(/can't cancel/)
    end
  end
end
