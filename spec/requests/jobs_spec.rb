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

      it "shows the job thread + each Run with its transcript and diff" do
        run = job.initial_run
        run.start!; run.succeed!
        run.update!(agent_diff: "diff --git a/foo b/foo\n+bar", agent_turns: 3, agent_outcome: "success")
        JobLog.create!(run: run, sequence: 0, chunk: "hello transcript")

        get job_path(job)
        expect(response).to be_successful
        expect(response.body).to include("acme/widgets")
        expect(response.body).to include("#42")
        expect(response.body).to include("hello transcript")
        expect(response.body).to include("diff --git")
        expect(response.body).to include("initial")  # trigger pill
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

    it "creates a new Job (hard reset, new branch + new PR) and enqueues an initial Run" do
      job
      expect {
        post replay_job_path(job)
      }.to change(Job, :count).by(1)
        .and have_enqueued_job(RunJob)

      new_job = Job.where(repository_id: repository.id, issue_number: 42).order(:created_at).last
      expect(new_job.id).not_to eq(job.id)
      expect(new_job.runs.size).to eq(1)
      expect(new_job.runs.first.trigger_kind).to eq("initial")
      expect(response).to redirect_to(job_path(new_job))
    end
  end

  describe "POST /jobs/:id/cancel" do
    before { sign_in_as(user) }

    it "cancels active runs and closes the Job thread" do
      run = job.initial_run
      run.start!; run.save!

      post cancel_job_path(job)

      job.reload
      run.reload
      expect(run.state).to eq("cancelled")
      expect(job.state).to eq("closed")
      expect(job.closure_reason).to eq("cancelled")
      expect(response).to redirect_to(job_path(job))
    end

    it "refuses to cancel an already-closed Job" do
      job.close_with_reason!("manual")
      post cancel_job_path(job)
      expect(flash[:alert]).to match(/already closed/)
    end
  end
end
