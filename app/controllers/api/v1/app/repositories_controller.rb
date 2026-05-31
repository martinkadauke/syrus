module Api
  module V1
    module App
      class RepositoriesController < BaseController
        def index
          render json: repositories_payload
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

        def find_repository
          Current.user.repositories.find(params[:id])
        end

        def agent_provider_label(provider)
          JobsHelper::AGENT_PROVIDER_LABELS[provider] || provider.to_s.titleize
        end
      end
    end
  end
end
