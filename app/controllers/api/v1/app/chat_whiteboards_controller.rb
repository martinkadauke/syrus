module Api
  module V1
    module App
      class ChatWhiteboardsController < BaseController
        def show
          render json: whiteboard_payload(find_chat_session.whiteboard)
        end

        def update
          chat_session = find_chat_session
          elements = params.fetch(:elements)
          unless elements.is_a?(Array)
            render_error("bad_request", "elements must be an array", status: :bad_request)
            return
          end

          if elements.size > Whiteboard::MAX_ELEMENTS
            render_error("element_limit", Whiteboard.element_limit_message, status: :unprocessable_content)
            return
          end

          expected_version = params.fetch(:expected_version).to_i
          status = :ok
          whiteboard = nil

          chat_session.with_lock do
            whiteboard = chat_session.whiteboard || chat_session.create_whiteboard!
            if expected_version == whiteboard.version
              whiteboard.replace_elements!(elements.map { |element| element.respond_to?(:to_unsafe_h) ? element.to_unsafe_h : element })
            else
              status = :conflict
            end
          end

          render json: whiteboard_payload(whiteboard), status: status
        end

        private

        def find_chat_session
          Current.user.chat_sessions.find(params[:id])
        end

        def whiteboard_payload(whiteboard)
          {
            scene_json: { elements: whiteboard&.elements || [] },
            version: whiteboard&.version || 0
          }
        end
      end
    end
  end
end
