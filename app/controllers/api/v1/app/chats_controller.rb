module Api
  module V1
    module App
      class ChatsController < BaseController
        def new
          render json: form_payload
        end

        def create
          chat_session = create_chat_session

          render json: {
            message: chat_session.messages.exists? ? "Message sent." : "Chat created.",
            redirect_to: chat_path(chat_session),
            chat: chat_json(chat_session)
          }, status: :created
        rescue ActiveRecord::LockWaitTimeout, ActiveRecord::Deadlocked
          render_error(
            "temporary_lock",
            "Chat creation was blocked by a temporary database lock. Try again.",
            status: :service_unavailable
          )
        end

        private

        def form_payload
          {
            repositories: Current.user.repositories.active.order(:owner, :name).map { |repository| repository_json(repository) },
            repositories_path: repositories_path
          }
        end

        def create_chat_session
          text = message_text
          repository = repository_from_params
          chat_session = nil
          user_message = nil

          ApplicationRecord.transaction do
            chat_session = ChatSession.create!(
              user: Current.user,
              repository: repository,
              title: text.presence&.truncate(80),
              last_message_at: text.present? ? Time.current : nil
            )
            if text.present?
              user_message = chat_session.messages.create!(role: "user", content: { "text" => text })
            end
          end

          ChatTurnJob.perform_later(chat_session.id, user_message.id) if user_message
          chat_session
        end

        def message_text
          params.dig(:chat_message, :text).to_s.strip
        end

        def repository_from_params
          id = params[:repository_id].presence
          return unless id

          Current.user.repositories.find(id)
        end

        def chat_json(chat_session)
          {
            id: chat_session.id,
            title: chat_session.title,
            chat_path: chat_path(chat_session),
            repository: chat_session.repository ? repository_json(chat_session.repository) : nil
          }
        end

        def repository_json(repository)
          {
            id: repository.id,
            slug: repository.slug
          }
        end
      end
    end
  end
end
