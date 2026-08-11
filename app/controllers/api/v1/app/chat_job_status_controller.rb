module Api
  module V1
    module App
      class ChatJobStatusController < BaseController
        def show
          chat_session = Current.user.accessible_chat_sessions.find(params[:chat_id])
          render json: ChatJobStatusQuery.call(chat_session)
        end
      end
    end
  end
end
