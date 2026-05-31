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

    describe "credential mode banner" do
      it "shows installed App status without a warning banner" do
        AppSetting.current.update!(github_app_id: 123, github_app_slug: "operator-syrus")
        installation = Factories.installation(user: user, account_login: "acme")
        repo = Factories.repository(user: user, owner: "acme", name: "widgets", installation: installation)

        get legacy_repository_path(repo)

        expect(response.body).to include("✓ Syrus App installed (via acme)")
        expect(response.body).not_to include("This repository is using personal-token fallback.")
      end

      it "shows a one-click install link when the App is registered but not installed" do
        AppSetting.current.update!(github_app_id: 123, github_app_slug: "operator-syrus")
        repo = Factories.repository(
          user: user,
          owner: "acme",
          name: "widgets",
          github_owner_id: 100,
          github_repository_id: 200
        )

        get legacy_repository_path(repo)

        expect(response.body).to include("This repository is using personal-token fallback.")
        expect(response.body).to include(
          "https://github.com/apps/operator-syrus/installations/new/permissions?target_id=100&amp;repository_ids[]=200"
        )
      end

      it "shows the manifest CTA when the App is not registered" do
        repo = Factories.repository(user: user)

        get legacy_repository_path(repo)

        expect(response.body).to include("Syrus App is not registered.")
        expect(response.body).to include("Register Syrus App")
      end

      it "shows PAT fallback when the recorded installation was removed" do
        AppSetting.current.update!(github_app_id: 123, github_app_slug: "operator-syrus")
        installation = Factories.installation(user: user, account_login: "acme", removed_at: Time.current)
        repo = Factories.repository(
          user: user,
          owner: "acme",
          name: "widgets",
          github_owner_id: 100,
          github_repository_id: 200
        )
        repo.update_column(:installation_id, installation.id)

        get legacy_repository_path(repo)

        expect(response.body).to include("Its previous installation was removed.")
        expect(response.body).to include("Install Syrus App on this repository")
      end
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

      it "renders the show page" do
        mine = Factories.repository(user: user, owner: "acme", name: "widgets")
        get repository_path(mine)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('id="syrus-spa-root"')
      end

      it "keeps the legacy show page available" do
        mine = Factories.repository(user: user, owner: "acme", name: "widgets")
        get legacy_repository_path(mine)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("acme/widgets")
      end

      it "renders active repository notes on the overview tab" do
        mine = Factories.repository(user: user)
        mine.repository_notes.create!(body: "Pinned deployment context.", author: "operator")
        mine.repository_notes.create!(body: "Removed context.", author: "agent", removed_at: Time.current)

        get legacy_repository_path(mine)

        expect(response.body).to include("Notes")
        expect(response.body).to include("Pinned deployment context.")
        expect(response.body).not_to include("Removed context.")
        expect(response.body).not_to include("Add note")
        expect(response.body).not_to include("Delete this repository note?")
      end

      it "shows the repository default agent on the show page" do
        mine = Factories.repository(user: user, agent_provider: "codex")
        get legacy_repository_path(mine)
        expect(response.body).to include("Agent:")
        expect(response.body).to include("Codex")
      end

      it "labels retry failed with the repository default agent" do
        mine = Factories.repository(user: user, agent_provider: "codex")
        failed = Factories.job(repository: mine)
        failed.current_run.update!(state: "failed", finished_at: Time.current)

        get legacy_repository_path(mine)

        expect(response.body).to include("Retry 1 failed with Codex")
        expect(response.body).to include("Retry 1 failed job(s) with Codex?")
      end

      it "shows only jobs belonging to this repository" do
        mine  = Factories.repository(user: user, owner: "acme", name: "widgets")
        other = Factories.repository(user: user, owner: "acme", name: "other")
        job_mine  = Factories.job(repository: mine)
        job_other = Factories.job(repository: other)

        get legacy_repository_path(mine)
        expect(response.body).to include(job_path(job_mine))
        expect(response.body).not_to include(job_path(job_other))
      end

      it "does not show another user's repository" do
        foreign = Factories.repository(user: other, owner: "globex", name: "things")
        get legacy_repository_path(foreign)
        expect(response).to have_http_status(:not_found)
      end

      it "links the slug to GitHub" do
        mine = Factories.repository(user: user, owner: "acme", name: "widgets")
        get legacy_repository_path(mine)
        expect(response.body).to include("https://github.com/acme/widgets")
      end

      describe "tabs" do
        let(:repo) { Factories.repository(user: user) }

        it "defaults to the overview tab" do
          get legacy_repository_path(repo)
          expect(response).to have_http_status(:ok)
          expect(response.body).to include("Overview")
          expect(response.body).to include("GitHub Issues")
          expect(response.body).not_to include(">Proposals</a>")
          # repository_chats_path is gone with the Repositories::ChatsController
          # retirement; the assertion that the overview tab didn't link to it
          # is also gone.
          expect(response.body).to include("Recent jobs")
        end

        it "does not route repository-scoped proposals" do
          expect {
            Rails.application.routes.recognize_path("/repositories/#{repo.id}/proposals", method: :get)
          }.to raise_error(ActionController::RoutingError)
        end

        it "renders the github_issues tab and fetches issues" do
          fake_issue = double("issue",
            number: 42, title: "Fix the thing", html_url: "https://github.com/test/repo/issues/42",
            body: "description", state: "open", labels: [], user: nil,
            created_at: 1.day.ago)
          allow(GithubClient).to receive(:for).and_return(
            instance_double(GithubClient, list_all_issues: [ fake_issue ])
          )

          get legacy_repository_path(repo, tab: "github_issues")
          expect(response).to have_http_status(:ok)
          expect(response.body).to include("Fix the thing")
          expect(response.body).not_to include("Recent jobs")
        end

        it "shows an alert on the github_issues tab when no token is configured" do
          allow(GithubClient).to receive(:for).and_raise(ArgumentError)

          get legacy_repository_path(repo, tab: "github_issues")
          expect(response).to have_http_status(:ok)
          expect(flash[:alert]).to match(/No GitHub token/)
        end

        it "shows an alert on the github_issues tab when GitHub returns an error" do
          allow(GithubClient).to receive(:for).and_return(
            instance_double(GithubClient).tap { |d|
              allow(d).to receive(:list_all_issues).and_raise(Octokit::Forbidden)
            }
          )

          get legacy_repository_path(repo, tab: "github_issues")
          expect(response).to have_http_status(:ok)
          expect(flash[:alert]).to match(/GitHub error/)
        end

        it "ignores unknown tab values and falls back to overview" do
          get legacy_repository_path(repo, tab: "hax")
          expect(response).to have_http_status(:ok)
          expect(response.body).to include("Recent jobs")
        end
      end

      describe "pagination" do
        let(:repo) { Factories.repository(user: user) }

        it "shows no pagination controls when jobs fit on one page" do
          3.times { |i| Factories.job(repository: repo, issue_number: i + 1) }
          get legacy_repository_path(repo)
          expect(response.body).not_to include("← Previous")
          expect(response.body).not_to include("Next →")
        end

        it "shows 'Showing X–Y of Z' counter and navigation when jobs exceed one page" do
          (RepositoriesController::PER_PAGE + 2).times { |i| Factories.job(repository: repo, issue_number: i + 1) }
          get legacy_repository_path(repo)
          total = RepositoriesController::PER_PAGE + 2
          expect(response.body).to include("Showing 1–#{RepositoriesController::PER_PAGE} of #{total}")
          expect(response.body).to include("Next →")
        end

        it "renders a disabled Previous button on page 1" do
          (RepositoriesController::PER_PAGE + 1).times { |i| Factories.job(repository: repo, issue_number: i + 1) }
          get legacy_repository_path(repo)
          expect(response.body).to match(/class="px-3 py-1 border border-gray-200 rounded text-gray-300"[^>]*>← Previous/)
        end

        it "renders a disabled Next button on the last page" do
          (RepositoriesController::PER_PAGE + 1).times { |i| Factories.job(repository: repo, issue_number: i + 1) }
          get legacy_repository_path(repo, page: 2)
          expect(response.body).to match(/class="px-3 py-1 border border-gray-200 rounded text-gray-300"[^>]*>Next →/)
        end

        it "shows the correct range on page 2" do
          (RepositoriesController::PER_PAGE + 3).times { |i| Factories.job(repository: repo, issue_number: i + 1) }
          get legacy_repository_path(repo, page: 2)
          total = RepositoriesController::PER_PAGE + 3
          expect(response.body).to include("Showing #{RepositoriesController::PER_PAGE + 1}–#{total} of #{total}")
        end
      end
    end
  end

  it "requires authentication on show" do
    repo = Factories.repository(user: user)
    get repository_path(repo)
    expect(response).to redirect_to(new_session_path)
  end
end
