class JobsController < ApplicationController
  before_action :load_job

  def show
  end

  def replay
    new_job = Current.user.jobs.create!(
      repository: @job.repository,
      issue_number: @job.issue_number
    )
    redirect_to job_path(new_job), notice: "Replay enqueued."
  end

  def cancel
    if @job.may_cancel?
      @job.cancel!
      redirect_to job_path(@job), notice: "Cancellation requested."
    else
      redirect_to job_path(@job), alert: "Job is already #{@job.state} — can't cancel."
    end
  end

  private

  def load_job
    @job = Current.user.jobs.includes(:repository, :job_logs).find(params[:id])
  end
end
