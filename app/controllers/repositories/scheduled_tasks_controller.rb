class Repositories::ScheduledTasksController < ApplicationController
  before_action :load_repository
  before_action :load_task, only: %i[ update destroy ]
  helper_method :repository_scheduled_tasks_index_path,
                :repository_scheduled_task_mutation_path,
                :new_repository_scheduled_task_entry_path

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
    redirect_to repository_scheduled_tasks_redirect_path, notice: notice
  end

  def destroy
    @scheduled_task.soft_delete!
    redirect_to repository_scheduled_tasks_redirect_path, notice: "Scheduled task deleted."
  end

  private

  def load_repository
    @repository = Current.user.repositories.find(params[:repository_id])
  end

  def load_task
    @scheduled_task = @repository.scheduled_tasks.find(params[:id])
  end

  def repository_scheduled_tasks_index_path
    legacy_repository_scheduled_tasks_request? ? repository_legacy_scheduled_tasks_path(@repository) : repository_scheduled_tasks_path(@repository)
  end

  def repository_scheduled_task_mutation_path(task)
    if legacy_repository_scheduled_tasks_request?
      repository_legacy_scheduled_task_path(@repository, task)
    else
      repository_scheduled_task_path(@repository, task)
    end
  end

  def new_repository_scheduled_task_entry_path
    if legacy_repository_scheduled_tasks_request?
      repository_legacy_new_scheduled_task_path(@repository)
    else
      new_repository_scheduled_task_path(@repository)
    end
  end

  def repository_scheduled_tasks_redirect_path
    legacy_repository_scheduled_tasks_request? ? repository_legacy_scheduled_tasks_path(@repository) : repository_scheduled_tasks_path(@repository)
  end

  def legacy_repository_scheduled_tasks_request?
    request.path.include?("/scheduled_tasks/legacy")
  end
end
