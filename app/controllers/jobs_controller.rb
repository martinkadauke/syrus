class JobsController < ApplicationController
  before_action :load_job

  def show
  end

  def replay
    new_job = Current.user.jobs.create!(
      repository: @job.repository,
      issue_number: @job.issue_number
    )
    redirect_to job_path(new_job), notice: "Replay enqueued — new branch and PR will be created."
  end

  def cancel
    if @job.closed?
      redirect_to job_path(@job), alert: "Job is already closed."
      return
    end

    @job.runs.active.find_each do |run|
      run.cancel! if run.may_cancel?
      run.save!
    end
    @job.close_with_reason!("cancelled")
    redirect_to job_path(@job), notice: "Cancellation requested."
  end

  private

  def load_job
    @job = Current.user.jobs.includes(:repository, runs: :job_logs).find(params[:id])
  end
end
