module Api
  module V1
    module App
      class RepositoriesController < BaseController
        def index
          render json: repositories_payload
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
