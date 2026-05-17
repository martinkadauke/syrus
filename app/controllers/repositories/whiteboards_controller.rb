class Repositories::WhiteboardsController < ApplicationController
  before_action :load_repository
  before_action :load_repository_whiteboard

  def show
    render json: whiteboard_payload
  end

  def update
    expected_version = params.require(:expected_version).to_i

    unless @repository_whiteboard.apply_elements!(params.fetch(:elements, []), expected_version: expected_version)
      @repository_whiteboard.reload
      render json: whiteboard_payload, status: :conflict
      return
    end

    render json: whiteboard_payload
  end

  private

  def load_repository
    @repository = Current.user.repositories.find(params[:repository_id])
  end

  def load_repository_whiteboard
    @repository_whiteboard = @repository.repository_whiteboard || @repository.create_repository_whiteboard!
  end

  # Frontend (app/javascript/controllers/whiteboard_controller.js) reads
  # `payload.scene_json.elements`. The flat `{ elements, version }`
  # shape that `Whiteboard#current_state` returns predates that, so
  # wrap it here to keep the response surface uniform with the
  # chat-scoped variant (ChatWhiteboardsController).
  def whiteboard_payload
    {
      scene_json: { elements: @repository_whiteboard.elements },
      version: @repository_whiteboard.version
    }
  end
end
