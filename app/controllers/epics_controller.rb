class EpicsController < ApplicationController
  PER_PAGE = 25

  before_action :load_epic

  def archive
    if @epic.archived?
      redirect_back fallback_location: epics_path, notice: "Epic already archived."
    else
      @epic.archive!
      redirect_to epics_path, notice: "Epic archived."
    end
  end

  def update_state
    target_state = params[:target_state].to_s

    if ActiveModel::Type::Boolean.new.cast(params[:override])
      @epic.override_state!(target_state)
      respond_to_state_update
    elsif @epic.backlog? && target_state == "ready" && @epic.may_auto_ready?
      @epic.auto_ready!
      respond_to_state_update
    elsif @epic.ready? && target_state == "in_progress"
      @epic.start!
      respond_to_state_update
    elsif @epic.in_progress? && target_state == "ready"
      @epic.unstart!
      respond_to_state_update
    elsif @epic.in_progress? && target_state == "done" && @epic.may_auto_complete?
      @epic.auto_complete!
      respond_to_state_update
    elsif target_state == "archived" && @epic.may_archive?
      @epic.archive!
      respond_to_state_update
    else
      respond_to do |format|
        format.html { redirect_back fallback_location: dashboard_epics_path, alert: "That Epic transition is not available." }
        format.json { render json: { error: "transition_not_allowed" }, status: :unprocessable_content }
      end
    end
  rescue ArgumentError
    respond_to do |format|
      format.html { redirect_back fallback_location: dashboard_epics_path, alert: "Unknown Epic state." }
      format.json { render json: { error: "unknown_state" }, status: :unprocessable_content }
    end
  end

  def graph
    @graph = EpicDependencyGraphRenderer.new(@epic).render
    html = render_to_string(partial: "dependency_graph", locals: {
      epic: @epic,
      result: @graph,
      initially_open: true,
      drawer: ActiveModel::Type::Boolean.new.cast(params[:drawer])
    })
    render html: helpers.safe_turbo_frame("epic_graph_drawer_body") { html.html_safe }
  end

  private

  def load_epic
    @epic = Current.user.epics.includes(:repository).find(params[:id])
  end

  def respond_to_state_update
    respond_to do |format|
      format.html { redirect_back fallback_location: dashboard_epics_path, notice: "Epic updated." }
      format.json { render json: { state: @epic.reload.state } }
    end
  end
end
