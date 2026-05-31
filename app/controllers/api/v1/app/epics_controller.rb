module Api
  module V1
    module App
      class EpicsController < BaseController
        def new
          render json: form_payload(Current.user.epics.new)
        end

        def edit
          render json: form_payload(find_epic)
        end

        def create
          epic = Current.user.epics.new(epic_params)

          if epic.save
            render json: saved_payload(epic, message: "Epic created."), status: :created
          else
            render_error("validation_failed", epic.errors.full_messages.to_sentence, status: :unprocessable_content)
          end
        end

        def update
          epic = find_epic

          if epic.update(epic_params)
            render json: saved_payload(epic, message: "Epic updated.")
          else
            render_error("validation_failed", epic.errors.full_messages.to_sentence, status: :unprocessable_content)
          end
        end

        private

        def form_payload(epic)
          {
            epic: epic_json(epic),
            repositories: Current.user.repositories.order(:name).map { |repository| repository_json(repository) },
            dashboard_epics_path: dashboard_epics_path
          }
        end

        def saved_payload(epic, message:)
          {
            message: message,
            redirect_to: epic_path(epic),
            epic: epic_json(epic)
          }
        end

        def epic_json(epic)
          {
            id: epic.id,
            title: epic.title.to_s,
            description: epic.description.to_s,
            repository_id: epic.repository_id,
            github_issue_url: epic.github_issue_url.to_s,
            epic_path: epic.persisted? ? epic_path(epic) : nil
          }
        end

        def repository_json(repository)
          {
            id: repository.id,
            slug: repository.slug
          }
        end

        def find_epic
          Current.user.epics.find(params[:id])
        end

        def epic_params
          params.require(:epic).permit(:title, :description, :repository_id, :github_issue_url)
        end
      end
    end
  end
end
