class HomeController < ApplicationController
  PER_PAGE = 25

  def index
    # Filter via subquery on Repository — that triggers Repository's
    # default_scope (archived excluded). We can't lean on
    # `Job.joins(:repository)` because Job's `belongs_to :repository`
    # explicitly unscopes (admin paths need to read archived parent
    # repos), so the join wouldn't apply the default scope.
    active_repo_ids = Current.user.repositories.select(:id)
    @repositories   = Current.user.repositories.order(:owner, :name)
    @active_tab     = params[:tab] == "workflows" ? "workflows" : "jobs"
    @page           = [ params[:page].to_i, 1 ].max

    # Eager-load workflows + their steps so current_step_caption(job)
    # doesn't N+1 against every row in the dashboard table.
    @jobs = Current.user.jobs.where(repository_id: active_repo_ids)
                             .includes(:repository, workflows: :steps)
    @jobs = @jobs.where(state: params[:state]) if params[:state].present?
    @jobs = @jobs.where(repository_id: params[:repository_id]) if params[:repository_id].present?

    case params[:pr]
    when "has_pr" then @jobs = @jobs.with_pr
    when "no_pr"  then @jobs = @jobs.without_pr
    end

    if params[:age].present?
      cutoff = { "1d" => 1.day.ago, "7d" => 7.days.ago, "30d" => 30.days.ago }[params[:age]]
      @jobs = @jobs.where(created_at: cutoff..) if cutoff
    end

    @jobs_total = @jobs.count
    @jobs = @jobs.order(created_at: :desc).offset((@page - 1) * PER_PAGE).limit(PER_PAGE)

    # Workflows tab — every burst of work, newest first. Eager-load
    # job→repository for the row, plus steps so the "currently"
    # caption can name the active step without an extra query.
    @workflows = Workflow.joins(:job)
                         .where(jobs: { user_id: Current.user.id, repository_id: active_repo_ids })
                         .includes(:steps, job: :repository)
    @workflows_total = @workflows.count
    @workflows = @workflows.order(created_at: :desc).offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
  end
end
