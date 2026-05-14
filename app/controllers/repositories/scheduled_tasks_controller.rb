class Repositories::ScheduledTasksController < ApplicationController
  before_action :load_repository
  before_action :load_task, only: %i[ update destroy ]

  # Per-repo lightweight view of ScheduledTask. The full operator
  # CRUD UI lives at the top-level /scheduled_tasks; this tab is a
  # focused per-repo list with enable / disable / delete affordances
  # so chat-created schedules can be managed in the same place the
  # operator was just talking to the agent.
  def index
    @scheduled_tasks = @repository
      .scheduled_tasks
      .alive
      .order(Arel.sql("CASE state WHEN 'scheduled' THEN 0 ELSE 1 END"), created_at: :desc)
  end

  def update
    enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled])
    if enabled
      @scheduled_task.resume!
      notice = "Scheduled task enabled."
    else
      @scheduled_task.pause!(reason: "operator")
      notice = "Scheduled task disabled."
    end
    redirect_to repository_scheduled_tasks_path(@repository), notice: notice
  end

  def destroy
    @scheduled_task.soft_delete!
    redirect_to repository_scheduled_tasks_path(@repository), notice: "Scheduled task deleted."
  end

  private

  def load_repository
    @repository = Current.user.repositories.find(params[:repository_id])
  end

  def load_task
    @scheduled_task = @repository.scheduled_tasks.find(params[:id])
  end
end
