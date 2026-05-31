module Api
  module V1
    module App
      class RepositoriesController < BaseController
        def index
          render json: repositories_payload
        end

        def show
          repository = find_repository
          page = [ params.fetch(:page, 1).to_i, 1 ].max

          render json: repository_detail_payload(repository, page: page)
        end

        def new
          render json: form_payload(Current.user.repositories.build(default_branch: "main", trigger_label: "syrus"))
        end

        def edit
          render json: form_payload(find_repository)
        end

        def owners
          render json: GithubClient.for_user(Current.user).accessible_owners
        rescue ArgumentError
          render json: { error: "no_token" }
        rescue Octokit::Unauthorized, Octokit::Forbidden
          render json: { error: "unauthorized" }
        rescue StandardError
          render json: { error: "error" }
        end

        def repos
          owner = params[:owner].to_s.strip
          return render json: { error: "missing_params" } if owner.blank?

          owner_type = params[:owner_type].to_s.strip
          render json: { repos: GithubClient.for_user(Current.user).owner_repos(owner, owner_type: owner_type) }
        rescue ArgumentError
          render json: { error: "no_token" }
        rescue Octokit::NotFound, Octokit::Unauthorized, Octokit::Forbidden
          render json: { error: "not_found" }
        rescue StandardError
          render json: { error: "error" }
        end

        def branches
          owner = params[:owner].to_s.strip
          name = params[:name].to_s.strip
          if owner.blank? || name.blank?
            render json: { error: "missing_params" }
            return
          end

          render json: GithubClient.for_user(Current.user).repo_branches("#{owner}/#{name}")
        rescue Octokit::NotFound, Octokit::Unauthorized, Octokit::Forbidden
          render json: { error: "not_found" }
        rescue StandardError
          render json: { error: "error" }
        end

        def create
          repository = Current.user.repositories.build(repository_params)

          if repository.save
            render json: saved_payload(repository, message: "Repository #{repository.slug} added."), status: :created
          else
            render_error("validation_failed", repository.errors.full_messages.to_sentence, status: :unprocessable_content)
          end
        end

        def update
          repository = find_repository

          if repository.update(repository_params)
            render json: saved_payload(repository, message: "Repository #{repository.slug} updated.")
          else
            render_error("validation_failed", repository.errors.full_messages.to_sentence, status: :unprocessable_content)
          end
        end

        def poll
          repository = find_repository
          if repository.archived?
            render_error("validation_failed", "#{repository.slug} is archived — unarchive it first.", status: :unprocessable_content)
            return
          end

          PollRepositoryJob.perform_later(repository.id, force: true)
          render json: repositories_payload(message: "Polling #{repository.slug} now.")
        end

        def archive
          repository = find_repository
          repository.archive!
          render json: repositories_payload(message: "#{repository.slug} archived.")
        end

        def unarchive
          repository = find_repository
          repository.unarchive!
          render json: repositories_payload(message: "#{repository.slug} unarchived. Re-enable polling to start ingestion again.")
        end

        private

        def form_payload(repository)
          {
            repository: repository_form_json(repository),
            configured_agent_providers: User::AGENT_PROVIDERS.map { |provider| provider_json(provider) },
            user_agent_provider_label: agent_provider_label(Current.user.agent_provider),
            auto_approve_modes: auto_approve_modes_json,
            repositories_path: repositories_path
          }
        end

        def saved_payload(repository, message:)
          {
            message: message,
            redirect_to: repositories_path,
            repository: repository_json(repository)
          }
        end

        def repository_detail_payload(repository, page:, message: nil)
          jobs_scope = repository.jobs
            .includes(:runs, :scheduled_task, workflows: :steps)
            .order(updated_at: :desc)
          total_jobs = repository.jobs.count
          total_pages = [ (total_jobs / ::RepositoriesController::PER_PAGE.to_f).ceil, 1 ].max
          jobs = jobs_scope
            .limit(::RepositoriesController::PER_PAGE)
            .offset((page - 1) * ::RepositoriesController::PER_PAGE)

          {
            message: message,
            repository: repository_detail_json(repository),
            tabs: repository_tabs_json(repository),
            counts: repository_counts_json(repository),
            retry_failed_jobs: retry_failed_jobs_json(repository),
            credential_status: credential_status_json(repository),
            notes: repository.repository_notes.active.order(created_at: :desc, id: :desc).map { |note| note_json(repository, note) },
            jobs: jobs.map { |job| job_json(job) },
            pagination: pagination_json(page: page, total_jobs: total_jobs, total_pages: total_pages, repository: repository),
            paths: {
              new_job_path: new_job_path(repository_id: repository.id),
              edit_repository_path: edit_repository_path(repository),
              poll_repository_path: poll_repository_path(repository),
              archive_repository_path: archive_repository_path(repository),
              retry_failed_jobs_repository_path: retry_failed_jobs_repository_path(repository),
              repository_notes_path: repository_notes_path(repository),
              repositories_path: repositories_path,
              repository_documents_path: repository_documents_path(repository),
              repository_scheduled_tasks_path: repository_scheduled_tasks_path(repository)
            }
          }
        end

        def repositories_payload(message: nil)
          repos = Current.user.repositories.order(:owner, :name)
          {
            active_repositories: repos.active.map { |repository| repository_json(repository) },
            archived_repositories: repos.archived.map { |repository| repository_json(repository) },
            new_repository_path: new_repository_path,
            message: message
          }
        end

        def repository_json(repository)
          {
            id: repository.id,
            slug: repository.slug,
            owner: repository.owner,
            name: repository.name,
            default_branch: repository.default_branch,
            trigger_label: repository.trigger_label,
            polling_enabled: repository.polling_enabled?,
            archived: repository.archived?,
            archived_at: repository.archived_at&.iso8601,
            agent_provider: repository.agent_provider,
            agent_provider_label: repository.agent_provider.present? ? agent_provider_label(repository.agent_provider) : "default",
            last_poll_status: repository.last_poll_status,
            last_poll_started_at: repository.last_poll_started_at&.iso8601,
            last_poll_error: repository.last_poll_error,
            repository_path: repository_path(repository),
            edit_repository_path: edit_repository_path(repository)
          }
        end

        def repository_detail_json(repository)
          repo_user = repository.user
          {
            id: repository.id,
            slug: repository.slug,
            owner: repository.owner,
            name: repository.name,
            default_branch: repository.default_branch,
            trigger_label: repository.trigger_label,
            polling_enabled: repository.polling_enabled?,
            archived: repository.archived?,
            agent_provider: repository.agent_provider,
            agent_provider_label: repository.agent_provider.present? ? agent_provider_label(repository.agent_provider) : nil,
            effective_agent_provider: repository.effective_agent_provider,
            effective_agent_provider_label: agent_provider_label(repository.effective_agent_provider),
            github_url: "https://github.com/#{repository.slug}",
            created_at: repository.created_at.iso8601,
            owner_user: {
              email_address: repo_user.email_address,
              admin: repo_user.admin?
            },
            github_rate_limit: github_rate_limit_json(repo_user)
          }
        end

        def repository_form_json(repository)
          {
            id: repository.id,
            owner: repository.owner.to_s,
            name: repository.name.to_s,
            slug: repository.persisted? ? repository.slug : nil,
            default_branch: repository.default_branch.to_s,
            trigger_label: repository.trigger_label.to_s,
            polling_enabled: repository.polling_enabled?,
            prepare_enabled: repository.prepare_enabled?,
            pr_cost_footer_enabled: repository.pr_cost_footer_enabled?,
            auto_merge_enabled: repository.auto_merge_enabled?,
            agent_provider: repository.agent_provider.to_s,
            auto_approve_mode: repository.auto_approve_mode,
            github_owner_id: repository.github_owner_id,
            github_repository_id: repository.github_repository_id,
            repository_path: repository.persisted? ? repository_path(repository) : nil
          }
        end

        def repository_tabs_json(repository)
          [
            { key: "overview", label: "Overview", path: repository_path(repository) },
            { key: "github_issues", label: "GitHub Issues", path: repository_path(repository, tab: "github_issues") },
            { key: "scheduled_tasks", label: "Scheduled Tasks", path: repository_scheduled_tasks_path(repository) }
          ]
        end

        def repository_counts_json(repository)
          {
            running: repository.jobs.joins(:runs).where(runs: { state: "running" }).distinct.count,
            queued: repository.jobs.joins(:runs).where(runs: { state: "queued" }).distinct.count,
            failed_7d: repository.jobs
              .joins(:runs)
              .where(runs: { state: "failed", updated_at: 7.days.ago.. })
              .distinct
              .count
          }
        end

        def retry_failed_jobs_json(repository)
          retryable = repository.jobs.open_threads.select { |job| !job.any_active_run? && job.current_run&.failed? }
          {
            count: retryable.size,
            agent_provider: repository.effective_agent_provider,
            agent_provider_label: agent_provider_label(repository.effective_agent_provider)
          }
        end

        def credential_status_json(repository)
          if repository.app_credential_active?
            return {
              mode: "app",
              label: "Syrus App installed",
              installation_account: repository.installation.account_login,
              github_app_registered: AppSetting.github_app_registered?,
              install_url: nil,
              register_path: nil,
              previous_installation_removed: false,
              missing_github_ids: false
            }
          end

          install_url = AppSetting.github_app_registered? ? helpers.github_app_install_url_for(repository) : nil
          {
            mode: "pat",
            label: "PAT fallback",
            installation_account: nil,
            github_app_registered: AppSetting.github_app_registered?,
            install_url: install_url,
            register_path: Current.user.admin? && !AppSetting.github_app_registered? ? admin_github_app_register_path : nil,
            previous_installation_removed: repository.installation&.removed_at.present?,
            missing_github_ids: AppSetting.github_app_registered? && install_url.blank?
          }
        end

        def github_rate_limit_json(user)
          return nil unless user.gh_rate_limit_observed_at

          {
            remaining: user.gh_rate_limit_remaining,
            limit: user.gh_rate_limit_limit,
            resource: user.gh_rate_limit_resource || "core",
            observed_at: user.gh_rate_limit_observed_at.iso8601
          }
        end

        def note_json(repository, note)
          {
            id: note.id,
            body: note.body,
            author: note.author,
            created_at: note.created_at.iso8601,
            delete_path: repository_note_path(repository, note)
          }
        end

        def job_json(job)
          {
            id: job.id,
            state: helpers.job_summary_state(job),
            priority: job.priority,
            issue_number: job.issue_number,
            issue_title: job.issue_title.to_s,
            job_path: job_path(job),
            source: job_source_json(job),
            pr_number: job.pr_number,
            pr_url: helpers.job_pr_url(job),
            external_pr_number: job.external_pr_number,
            external_pr_url: helpers.external_pr_url(job),
            current_step_caption: helpers.current_step_caption(job),
            runs_count: job.runs.size,
            updated_at: job.updated_at.iso8601
          }
        end

        def job_source_json(job)
          if job.cron?
            task = job.scheduled_task
            return {
              label: task ? "scheduled: #{task.name}" : "scheduled task ##{job.scheduled_task_id}",
              path: task ? scheduled_task_path(task) : nil,
              external: false
            }
          end

          if job.direct?
            return { label: "Direct", path: nil, external: false }
          end

          {
            label: "##{job.issue_number}",
            path: helpers.job_issue_url(job),
            external: true
          }
        end

        def pagination_json(page:, total_jobs:, total_pages:, repository:)
          first_item = total_jobs.zero? ? 0 : ((page - 1) * ::RepositoriesController::PER_PAGE) + 1
          last_item = [ page * ::RepositoriesController::PER_PAGE, total_jobs ].min

          {
            page: page,
            per_page: ::RepositoriesController::PER_PAGE,
            total_jobs: total_jobs,
            total_pages: total_pages,
            first_item: first_item,
            last_item: last_item,
            previous_path: page > 1 ? repository_path(repository, page: page - 1) : nil,
            next_path: page < total_pages ? repository_path(repository, page: page + 1) : nil
          }
        end

        def provider_json(provider)
          {
            value: provider,
            label: agent_provider_label(provider)
          }
        end

        def auto_approve_modes_json
          [
            {
              value: "never",
              label: "Never",
              preview: "No direct rule; Jobs can still inherit a repository or user default."
            },
            {
              value: "if_graders_pass",
              label: "If graders pass",
              preview: "Jobs using this rule enter landing after repo-committed graders pass."
            },
            {
              value: "if_graders_pass_and_tagged_safe",
              label: "If graders pass and tagged safe",
              preview: "Jobs using this rule also need the safe tag before landing."
            }
          ]
        end

        def find_repository
          Current.user.repositories.find(params[:id])
        end

        def repository_params
          params.require(:repository).permit(
            :owner,
            :name,
            :default_branch,
            :trigger_label,
            :polling_enabled,
            :prepare_enabled,
            :agent_provider,
            :pr_cost_footer_enabled,
            :auto_merge_enabled,
            :auto_approve_mode,
            :github_repository_id,
            :github_owner_id
          )
        end

        def agent_provider_label(provider)
          JobsHelper::AGENT_PROVIDER_LABELS[provider] || provider.to_s.titleize
        end
      end
    end
  end
end
