require "rails_helper"

RSpec.describe "Repositories", type: :request do
  let(:user)  { Factories.user }
  let(:other) { Factories.user }

  it "requires authentication on index" do
    user  # force a User to exist; first-run setup redirects to new_user instead
    get repositories_path
    expect(response).to redirect_to(new_session_path)
  end

  context "signed in" do
    before { sign_in_as(user) }

    it "serves the React app shell" do
      get repositories_path

      expect(response).to be_successful
      expect(response.body).to include('id="syrus-spa-root"')
    end

    it "serves the React app shell for new and edit forms" do
      mine = Factories.repository(user: user, owner: "acme", name: "widgets")

      get new_repository_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="syrus-spa-root"')

      get edit_repository_path(mine)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="syrus-spa-root"')
    end

    it "does not route retired repository list and form endpoints" do
      expect {
        Rails.application.routes.recognize_path("/repositories/legacy", method: :get)
      }.to raise_error(ActionController::RoutingError)
      expect {
        Rails.application.routes.recognize_path("/repositories/new/legacy", method: :get)
      }.to raise_error(ActionController::RoutingError)
      expect {
        Rails.application.routes.recognize_path("/repositories/1/edit/legacy", method: :get)
      }.to raise_error(ActionController::RoutingError)
      expect {
        Rails.application.routes.recognize_path("/repositories", method: :post)
      }.to raise_error(ActionController::RoutingError)
      expect {
        Rails.application.routes.recognize_path("/repositories/1", method: :patch)
      }.to raise_error(ActionController::RoutingError)
    end

    it "has no destroy route — Archive is the only retire path" do
      mine = Factories.repository(user: user)
      # DELETE /repositories/:id is no longer routable (resources
      # uses except: [:destroy]); the request 404s and the row stays.
      expect {
        delete "/repositories/#{mine.id}" rescue nil
      }.not_to change(user.repositories, :count)
    end

    it "manual poll enqueues PollRepositoryJob with force: true" do
      mine = Factories.repository(user: user, polling_enabled: false)
      expect {
        post poll_repository_path(mine)
      }.to have_enqueued_job(PollRepositoryJob).with(mine.id, force: true)
      expect(response).to redirect_to(repository_path(mine))
      expect(flash[:notice]).to match(/Polling/)
    end

    describe "archive / unarchive" do
      it "archive stamps archived_at + flips polling off" do
        mine = Factories.repository(user: user, polling_enabled: true)
        post archive_repository_path(mine)
        expect(response).to redirect_to(repositories_path)
        expect(mine.reload).to be_archived
        expect(mine.polling_enabled).to be false
      end

      it "unarchive clears archived_at" do
        mine = Factories.repository(user: user)
        mine.archive!
        post unarchive_repository_path(mine)
        expect(response).to redirect_to(repositories_path)
        expect(mine.reload).not_to be_archived
      end

      it "archive/unarchive on another user's repo is not found" do
        foreign = Factories.repository(user: other)
        post archive_repository_path(foreign)
        expect(response).to have_http_status(:not_found).or redirect_to(repositories_path)
      end

      it "manual poll on an archived repo is rejected (does not enqueue)" do
        mine = Factories.repository(user: user)
        mine.archive!
        expect {
          post poll_repository_path(mine)
        }.not_to have_enqueued_job(PollRepositoryJob)
        expect(response).to redirect_to(repositories_path)
        expect(flash[:alert]).to match(/archived/)
      end

    end

    describe "repository notes" do
      it "does not route the retired legacy HTML note endpoints" do
        mine = Factories.repository(user: user)
        expect {
          Rails.application.routes.recognize_path("/repositories/#{mine.id}/notes", method: :post)
        }.to raise_error(ActionController::RoutingError)
        expect {
          Rails.application.routes.recognize_path("/repositories/#{mine.id}/notes/1", method: :delete)
        }.to raise_error(ActionController::RoutingError)
      end
    end

    describe "POST /repositories/:id/retry_failed_jobs" do
      let(:repo) { Factories.repository(user: user) }

      def fail_latest_run!(job)
        run = job.current_run
        run.update!(state: "failed", finished_at: Time.current)
      end

      it "spawns a Retry workflow for each failed open Job and counts them" do
        failed_a = Factories.job(repository: repo, issue_number: 1)
        failed_b = Factories.job(repository: repo, issue_number: 2)
        succeeded = Factories.job(repository: repo, issue_number: 3)
        running   = Factories.job(repository: repo, issue_number: 4)
        closed    = Factories.job(repository: repo, issue_number: 5)

        fail_latest_run!(failed_a)
        fail_latest_run!(failed_b)
        succeeded.current_run.update!(state: "succeeded", finished_at: Time.current)
        running.current_run.update!(state: "running", started_at: Time.current)
        closed.close!; closed.save!

        expect {
          post retry_failed_jobs_repository_path(repo)
        }.to change { Workflow.where(trigger_kind: "retry").count }.by(2)

        expect(response).to redirect_to(repository_path(repo))
        expect(flash[:notice]).to match(/2 failed jobs/)
      end

      it "uses the current user's preferred agent and persists it on each retried Job" do
        failed_a = Factories.job(repository: repo, issue_number: 1)
        failed_b = Factories.job(repository: repo, issue_number: 2)
        fail_latest_run!(failed_a)
        fail_latest_run!(failed_b)
        user.update!(agent_provider: "codex", codex_auth_mode: "api_key", codex_api_key: "sk-test")

        post retry_failed_jobs_repository_path(repo)

        [ failed_a, failed_b ].each do |failed_job|
          retry_workflow = failed_job.reload.workflows.where(trigger_kind: "retry").last
          expect(failed_job.agent_provider).to eq("codex")
          expect(retry_workflow.agent_provider).to eq("codex")
          expect(retry_workflow.first_step.runs.last.agent_provider).to eq("codex")
        end
        expect(flash[:notice]).to match(/with Codex/)
      end

      it "uses the repository default agent when one is specified" do
        repo.update!(agent_provider: "codex")
        failed_a = Factories.job(repository: repo, issue_number: 1)
        failed_b = Factories.job(repository: repo, issue_number: 2)
        fail_latest_run!(failed_a)
        fail_latest_run!(failed_b)

        post retry_failed_jobs_repository_path(repo)

        [ failed_a, failed_b ].each do |failed_job|
          retry_workflow = failed_job.reload.workflows.where(trigger_kind: "retry").last
          expect(failed_job.agent_provider).to eq("codex")
          expect(retry_workflow.agent_provider).to eq("codex")
          expect(retry_workflow.first_step.runs.last.agent_provider).to eq("codex")
        end
        expect(flash[:notice]).to match(/with Codex/)
      end

      it "returns an alert when no Jobs need retrying" do
        Factories.job(repository: repo, issue_number: 1)  # has only a queued initial run
        post retry_failed_jobs_repository_path(repo)
        expect(flash[:alert]).to match(/No failed jobs/)
      end

      it "scopes to the current user (other user's repo is 404)" do
        foreign = Factories.repository(user: other)
        post retry_failed_jobs_repository_path(foreign)
        expect(response).to have_http_status(:not_found).or redirect_to(repositories_path)
      end
    end

    describe "legacy repository selector helpers" do
      it "does not route retired repository form JSON helpers" do
        expect {
          Rails.application.routes.recognize_path("/repositories/owners", method: :get)
        }.to raise_error(ActionController::RoutingError)
        expect {
          Rails.application.routes.recognize_path("/repositories/repos", method: :get)
        }.to raise_error(ActionController::RoutingError)
        expect {
          Rails.application.routes.recognize_path("/repositories/branches", method: :get)
        }.to raise_error(ActionController::RoutingError)
      end
    end

    describe "GET /repositories/:id" do
      it "requires authentication" do
        # tested via the outer unauthenticated context below
      end

      it "serves the React app shell" do
        mine = Factories.repository(user: user, owner: "acme", name: "widgets")
        get repository_path(mine)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('id="syrus-spa-root"')
      end

      it "does not route the retired legacy detail page" do
        expect {
          Rails.application.routes.recognize_path("/repositories/1/legacy", method: :get)
        }.to raise_error(ActionController::RoutingError)
      end

      it "does not route repository-scoped proposals" do
        mine = Factories.repository(user: user)

        expect {
          Rails.application.routes.recognize_path("/repositories/#{mine.id}/proposals", method: :get)
        }.to raise_error(ActionController::RoutingError)
      end
    end
  end

  it "requires authentication on show" do
    repo = Factories.repository(user: user)
    get repository_path(repo)
    expect(response).to redirect_to(new_session_path)
  end
end
